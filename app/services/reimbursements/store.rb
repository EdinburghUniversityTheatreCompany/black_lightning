module Reimbursements
  ##
  # Cache-fronted repository — the only thing controllers and jobs may talk
  # to. Raw Airtable record hashes are cached in Solid Cache (mapping to POROs
  # happens per call; records are few) so a warm-cache portal visit costs zero
  # Airtable API calls — the workspace is on the free plan (~1,000 calls/month
  # shared with bedlam-bacs). One global expense list serves every visitor;
  # per-person filtering happens in Ruby. Every write busts the relevant key.
  class Store
    EXPENSES_KEY = "reimbursements/expenses".freeze
    EXPENSES_TTL = 10.minutes
    PEOPLE_KEY = "reimbursements/people".freeze
    PEOPLE_TTL = 1.hour
    BUDGETS_KEY = "reimbursements/budgets".freeze
    BUDGETS_TTL = 1.hour

    def initialize(client: nil, config: nil, cache: Rails.cache)
      @config = config || Airtable::Config.from_credentials
      @client = client || Airtable::Client.new(config: @config)
      @mapper = Airtable::Mapper.new(@config)
      @cache = cache
    end

    def expenses
      people_by_id = people.index_by(&:record_id)
      budgets_by_id = budgets.index_by(&:record_id)
      raw_expenses.map { |r| @mapper.expense(r, people_by_id: people_by_id, budgets_by_id: budgets_by_id) }
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

    def people
      raw = @cache.fetch(PEOPLE_KEY, expires_in: PEOPLE_TTL) { @client.list_records(:people) }
      raw.map { |r| @mapper.person(r) }
    end

    def person_by_email(email)
      return nil if email.blank?

      people.find { |p| p.email.strip.casecmp?(email.strip) }
    end

    def find_person(record_id)
      people.find { |p| p.record_id == record_id }
    end

    def budgets
      raw = @cache.fetch(BUDGETS_KEY, expires_in: BUDGETS_TTL) { @client.list_records(:budgets) }
      raw.map { |r| @mapper.budget(r) }
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

    def create_person!(name:, email:)
      record = @client.create_record(:people, @mapper.person_fields(name: name, email: email))
      @cache.delete(PEOPLE_KEY)
      @mapper.person(record)
    end

    def update_person!(record_id, attrs)
      record = @client.update_record(:people, record_id, @mapper.person_fields(attrs))
      @cache.delete(PEOPLE_KEY)
      @mapper.person(record)
    end

    def bust_expenses!
      @cache.delete(EXPENSES_KEY)
    end
    alias refresh_expenses! bust_expenses!

    private

    def raw_expenses
      @cache.fetch(EXPENSES_KEY, expires_in: EXPENSES_TTL) { @client.list_records(:expenses) }
    end

    def map_single_expense(record)
      @mapper.expense(record,
                      people_by_id: people.index_by(&:record_id),
                      budgets_by_id: budgets.index_by(&:record_id))
    end
  end
end
