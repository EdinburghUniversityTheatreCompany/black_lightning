module Reimbursements
  ##
  # The ActiveRecord-backed repository — the same frozen public API as the
  # Airtable-backed Store, selected by Reimbursements.build_store when
  # REIMBURSEMENTS_BACKEND=database (the MySQL cutover flip). At the post-flip
  # cleanup this class absorbs the Store name and the Airtable one is deleted.
  #
  # No cache layer: the Solid-Cache read-through existed solely to ration the
  # Airtable free plan. Lists are memoized per instance (one store per
  # request/job run) so repeated reads in one render cost one query.
  #
  # Writers accept the Store's established attribute vocabulary
  # (person_record_id/budget_record_id/batch_id strings, arrays for
  # sharepoint_receipt_urls and linked_*_ids) so no caller changes; nil values
  # are dropped exactly like the Airtable field writers so email-in
  # submissions can be created with gaps.
  class DatabaseStore
    include StoreQueries

    # Attribute-vocabulary translations onto AR columns; everything else in
    # the vocabulary already matches its column name.
    EXPENSE_KEY_MAP = { person_record_id: :person_id, budget_record_id: :budget_id }.freeze
    PERSON_FIELDS = %i[name email].freeze
    PAYMENT_DETAILS_FIELDS = %i[sort_code account_number verified notes].freeze

    def expenses
      @expenses ||= Expense.includes(:person, :budget, :batch).to_a
    end

    def people
      @people ||= Person.includes(:payment_details).to_a
    end

    def budgets
      @budgets ||= Budget.includes(:owners, :forecasts).to_a
    end

    def update_budget!(record_id, attrs)
      budget = Budget.find(record_id)
      attrs = attrs.compact
      owner_ids = attrs.delete(:owner_ids)
      budget.update!(attrs)
      sync_budget_owners(budget, owner_ids) unless owner_ids.nil?
      bust_budgets!
      budget
    end

    def budget_forecasts(budget_id)
      return [] if budget_id.blank?

      BudgetForecast.where(budget_id: budget_id)
                    .order(date: :desc, id: :desc).to_a
    end

    def create_forecast!(budget_id:, amount:, date:, reason:)
      forecast = BudgetForecast.create!(budget_id: budget_id, amount: amount,
                                        date: date, reason: reason)
      bust_budgets!
      forecast
    end

    def update_forecast!(record_id, amount:, date:, reason:)
      forecast = BudgetForecast.find(record_id)
      forecast.update!(amount: amount, date: date, reason: reason)
      bust_budgets!
      forecast
    end

    def delete_forecast!(record_id)
      BudgetForecast.find(record_id).destroy!
      bust_budgets!
    end

    def create_expense!(attrs)
      expense = Expense.create!(expense_columns(attrs)
                                  .reverse_merge(financial_year: FinancialYear.current))
      bust_expenses!
      expense
    end

    # Hard-delete; only used for a producer discarding their own draft — the
    # caller gates on status.
    def delete_expense!(record_id)
      Expense.find(record_id).destroy!
      bust_expenses!
    end

    def update_expense!(record_id, attrs)
      expense = Expense.find(record_id)
      columns = expense_columns(attrs)
      # A blank budget on the finance edit forms means "clear the budget" —
      # nil-compaction would otherwise make the link settable but never
      # removable (same explicit-clear the Airtable store performs).
      columns[:budget_id] = nil if attrs.key?(:budget_record_id) && attrs[:budget_record_id].blank?
      expense.update!(columns)
      bust_expenses!
      expense
    end

    def attach_receipt!(expense_record_id, filename:, content_type:, bytes:)
      Expense.find(expense_record_id).receipt_files
             .attach(io: StringIO.new(bytes), filename: filename, content_type: content_type)
      bust_expenses!
    end

    # Refuses to leave a non-draft receipt-less, exactly like the Airtable
    # store (drafts don't require one). attachment_id is the blob signed id
    # the Attachment wrapper exposes.
    def remove_receipt!(expense_record_id, attachment_id)
      expense = Expense.find(expense_record_id)
      target = expense.receipt_files.find { |file| file.signed_id == attachment_id }
      return bust_expenses! if target.nil?

      survivors = expense.receipt_files.reject { |file| file.signed_id == attachment_id }
      raise Store::LastReceiptError if survivors.empty? && expense.receipt_files.any? && !expense.draft?

      target.purge
      bust_expenses!
    end

    # Reverts a submitted expense to Approved, unlinking it from its batch so
    # it re-enters Build Batch cleanly. Deliberately leaves producer_notified
    # untouched so a rebuild won't re-email the producer.
    def revert_expense_to_approved!(record_id)
      Expense.find(record_id).update!(status: Status::APPROVED, batch_id: nil,
                                      submitted_to_eusa_date: nil, receipts_offloaded: false,
                                      sharepoint_receipt_urls: "")
      bust_expenses!
    end

    def batches
      @batches ||= Batch.order(:id).to_a
    end

    def find_batch_by_draft_message_id(message_id)
      return nil if message_id.blank?

      Batch.find_by(draft_message_id: message_id)
    end

    # Mailbox idempotency (the deferred-robustness fix Airtable couldn't
    # store): the poll job stamps the Graph message id on the expense it
    # creates and skips a message it has already seen.
    def supports_message_idempotency? = true

    def expense_for_source_message(message_id)
      return nil if message_id.blank?

      Expense.find_by(source_message_id: message_id)
    end

    def create_batch!(attrs)
      batch = Batch.create!(batch_columns(attrs))
      bust_batches!
      batch
    end

    def update_batch!(record_id, attrs)
      batch = Batch.find(record_id)
      batch.update!(batch_columns(attrs))
      bust_batches!
      batch
    end

    def delete_batch!(record_id)
      Batch.find(record_id).destroy!
      bust_batches!
    end

    def create_person!(name:, email:)
      person = Person.create!(name: name, email: email)
      bust_people!
      person
    end

    # The People page and the portal's Payment Details page send a mix of
    # Person columns and bank fields; the bank fields route to the linked
    # PaymentDetails record (created on first write).
    def update_person!(record_id, attrs)
      person = Person.find(record_id)
      attrs = attrs.compact
      person.update!(attrs.slice(*PERSON_FIELDS)) if attrs.keys.intersect?(PERSON_FIELDS)
      details_attrs = attrs.slice(*PAYMENT_DETAILS_FIELDS)
      if details_attrs.any?
        details = person.payment_details || person.build_payment_details
        details.update!(details_attrs)
      end
      bust_people!
      person
    end

    def bust_expenses!
      @expenses = nil
    end
    alias refresh_expenses! bust_expenses!

    # --- EUSA Actuals (reconciliation) ------------------------------------

    def eusa_actuals
      @eusa_actuals ||= EusaActual.includes(:expense, :budget).to_a
    end

    def create_actual!(attrs)
      actual = EusaActual.create!(actual_columns(attrs)
                                    .reverse_merge(financial_year: FinancialYear.current))
      bust_eusa_actuals!
      actual
    end

    def link_actual_to_expense!(actual_id, expense_id)
      actual = EusaActual.find(actual_id)
      actual.update!(expense_id: expense_id)
      bust_eusa_actuals!
      actual
    end

    def link_actual_to_budget!(actual_id, budget_id)
      actual = EusaActual.find(actual_id)
      actual.update!(budget_id: budget_id)
      bust_eusa_actuals!
      actual
    end

    private

    def bust_eusa_actuals!
      @eusa_actuals = nil
    end

    def bust_people!
      @people = nil
    end

    def bust_batches!
      @batches = nil
    end

    def bust_budgets!
      @budgets = nil
    end

    def fetch_expense(record_id)
      expense = Expense.find_by(id: record_id)
      return nil if expense.nil?

      @expenses = ((@expenses || []).reject { |e| e.record_id == expense.record_id } + [ expense ])
      expense
    end

    def sync_budget_owners(budget, owner_record_ids)
      person_ids = Array(owner_record_ids).reject(&:blank?).map(&:to_i)
      budget.budget_ownerships.where.not(person_id: person_ids).destroy_all
      (person_ids - budget.budget_ownerships.pluck(:person_id)).each do |person_id|
        budget.budget_ownerships.create!(person_id: person_id)
      end
    end

    # nil values are dropped (email-in gaps); the sharepoint URL array joins
    # into the newline column.
    def expense_columns(attrs)
      attrs.compact.each_with_object({}) do |(key, value), columns|
        case key
        when :person_record_id, :budget_record_id then columns[EXPENSE_KEY_MAP.fetch(key)] = value
        when :sharepoint_receipt_urls then columns[key] = Array(value).join("\n")
        else columns[key] = value
        end
      end
    end

    # eusa_draft_created is derived from draft_message_id/date_sent on MySQL;
    # BatchProcessor still sends the flag for the Airtable backend, so it is
    # dropped rather than rejected here.
    def batch_columns(attrs)
      attrs.compact.except(:eusa_draft_created)
    end

    def actual_columns(attrs)
      attrs.compact.each_with_object({}) do |(key, value), columns|
        case key
        when :linked_expense_ids then columns[:expense_id] = Array(value).first
        when :linked_budget_ids then columns[:budget_id] = Array(value).first
        else columns[key] = value
        end
      end
    end
  end
end
