module Reimbursements
  ##
  # Cache-fronted repository — the only thing controllers and jobs may talk
  # to. Raw Airtable record hashes are cached in Solid Cache and the mapped
  # POROs are memoized per Store instance (one instance per request/job run),
  # so a warm-cache portal visit costs zero Airtable API calls — the
  # workspace is on the free plan (~1,000 calls/month shared with
  # bedlam-bacs). One global expense list serves every visitor; per-person
  # filtering happens in Ruby. Every write busts the relevant key.
  #
  # Each list also keeps a long-lived backup copy so an Airtable outage
  # serves day-old data instead of a 500.
  class Store
    EXPENSES_KEY = "reimbursements/expenses".freeze
    EXPENSES_TTL = 10.minutes
    PEOPLE_KEY = "reimbursements/people".freeze
    PEOPLE_TTL = 1.hour
    BUDGETS_KEY = "reimbursements/budgets".freeze
    BUDGETS_TTL = 1.hour
    EUSA_ACTUALS_KEY = "reimbursements/eusa_actuals".freeze
    EUSA_ACTUALS_TTL = 10.minutes
    BACKUP_TTL = 7.days

    # Raised instead of rewriting an expense's attachment field to empty.
    class LastReceiptError < StandardError; end

    def initialize(client: nil, config: nil, cache: Rails.cache)
      @config = config || Airtable::Config.from_credentials
      @client = client || Airtable::Client.new(config: @config)
      @mapper = Airtable::Mapper.new(@config)
      @cache = cache
    end

    def expenses
      @expenses ||= raw_expenses.map do |record|
        @mapper.expense(record, people_by_id: people_by_id, budgets_by_id: budgets_by_id)
      end
    end

    def expenses_for(person_record_id)
      return [] if person_record_id.blank?

      expenses.select { |e| e.person&.record_id == person_record_id }
              .sort_by { |e| e.submitted_at || Time.zone.at(0) }
              .reverse
    end

    def find_expense(record_id)
      expenses.find { |e| e.record_id == record_id }
    end

    # By-id lookup that survives a stale cached list (e.g. the expense was
    # created by the poll job in another process): on a miss it fetches the
    # single record fresh (1 API call) and folds it into this instance.
    def find_expense!(record_id)
      find_expense(record_id) || fetch_expense(record_id)
    end

    def people
      @people ||= fetch_list(PEOPLE_KEY, PEOPLE_TTL, :people).map { |r| @mapper.person(r) }
    end

    def person_by_email(email)
      return nil if email.blank?

      people.find { |p| p.email.strip.casecmp?(email.strip) }
    end

    def find_person(record_id)
      people.find { |p| p.record_id == record_id }
    end

    def budgets
      @budgets ||= fetch_list(BUDGETS_KEY, BUDGETS_TTL, :budgets).map { |r| @mapper.budget(r) }
    end

    # Budgets a submitter may charge an expense to.
    def active_budgets
      budgets.select { |b| b.active && !b.income? }.sort_by(&:name)
    end

    def create_expense!(attrs)
      record = @client.create_record(:expenses, @mapper.expense_fields(attrs))
      bust_expenses!
      map_single_expense(record)
    end

    def update_expense!(record_id, attrs)
      record = @client.update_record(:expenses, record_id, @mapper.expense_fields(attrs))
      bust_expenses!
      map_single_expense(record)
    end

    def attach_receipt!(expense_record_id, filename:, content_type:, bytes:)
      @client.upload_attachment(expense_record_id, table: :expenses, field: :receipt,
                                filename: filename, content_type: content_type, bytes: bytes)
      bust_expenses!
    end

    # Airtable removes an attachment by rewriting the field with the
    # survivors. Works from a FRESH fetch of the record (never the cached
    # list) so receipts attached elsewhere moments ago can't be wiped, and
    # refuses to leave a non-draft receipt-less (drafts don't require one).
    def remove_receipt!(expense_record_id, attachment_id)
      expense = fetch_expense(expense_record_id)
      raise Airtable::Error.new("expense #{expense_record_id} not found", status: 404) if expense.nil?

      survivors = expense.receipts.reject { |receipt| receipt.attachment_id == attachment_id }
      raise LastReceiptError if survivors.empty? && expense.receipts.any? && !expense.draft?

      @client.update_record(:expenses, expense_record_id,
                            @config.fid(:expenses, :receipt) => survivors.map { |r| { "id" => r.attachment_id } })
      bust_expenses!
    end

    def create_person!(name:, email:)
      record = @client.create_record(:people, @mapper.person_fields(name: name, email: email))
      bust_people!
      @mapper.person(record)
    end

    def update_person!(record_id, attrs)
      record = @client.update_record(:people, record_id, @mapper.person_fields(attrs))
      bust_people!
      @mapper.person(record)
    end

    def bust_expenses!
      @expenses = nil
      @cache.delete(EXPENSES_KEY)
    end
    alias refresh_expenses! bust_expenses!

    # --- EUSA Actuals (reconciliation) ------------------------------------

    # Every EUSA Actuals row already imported, mapped to POROs.
    def eusa_actuals
      @eusa_actuals ||= fetch_list(EUSA_ACTUALS_KEY, EUSA_ACTUALS_TTL, :eusa_actuals)
                        .map { |r| @mapper.eusa_actual(r) }
    end

    # Actuals imported for a given source month (YYYY-MM), used to dedup a
    # freshly-pasted export against what's already in Airtable.
    def actuals_for_month(source_month)
      eusa_actuals.select { |a| a.source_month == source_month }
    end

    def create_actual!(attrs)
      record = @client.create_record(:eusa_actuals, @mapper.eusa_actual_fields(attrs))
      bust_eusa_actuals!
      @mapper.eusa_actual(record)
    end

    def link_actual_to_expense!(actual_id, expense_id)
      record = @client.update_record(:eusa_actuals, actual_id,
                                     @mapper.eusa_actual_fields(linked_expense_ids: [ expense_id ]))
      bust_eusa_actuals!
      @mapper.eusa_actual(record)
    end

    def link_actual_to_budget!(actual_id, budget_id)
      record = @client.update_record(:eusa_actuals, actual_id,
                                     @mapper.eusa_actual_fields(linked_budget_ids: [ budget_id ]))
      bust_eusa_actuals!
      @mapper.eusa_actual(record)
    end

    private

    def bust_eusa_actuals!
      @eusa_actuals = nil
      @cache.delete(EUSA_ACTUALS_KEY)
    end

    def bust_people!
      @people = nil
      @cache.delete(PEOPLE_KEY)
    end

    def people_by_id
      @people_by_id ||= people.index_by(&:record_id)
    end

    def budgets_by_id
      @budgets_by_id ||= budgets.index_by(&:record_id)
    end

    def raw_expenses
      fetch_list(EXPENSES_KEY, EXPENSES_TTL, :expenses)
    end

    # Cache-fronted list fetch with a long-lived backup: when Airtable is
    # down and the fresh key has expired, serve the last-good copy.
    def fetch_list(key, ttl, table)
      @cache.fetch(key, expires_in: ttl) do
        records = @client.list_records(table)
        @cache.write("#{key}/backup", records, expires_in: BACKUP_TTL)
        records
      end
    rescue Airtable::Error => e
      backup = @cache.read("#{key}/backup")
      raise if backup.nil?

      Rails.logger.warn("Airtable unavailable (#{e.message}); serving backup for #{key}")
      backup
    end

    def fetch_expense(record_id)
      record = @client.get_record(:expenses, record_id)
      return nil if record.nil?

      expense = map_single_expense(record)
      @expenses = ((@expenses || []).reject { |e| e.record_id == record_id } + [ expense ])
      expense
    end

    def map_single_expense(record)
      @mapper.expense(record, people_by_id: people_by_id, budgets_by_id: budgets_by_id)
    end
  end
end
