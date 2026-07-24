module Reimbursements
  ##
  # The ActiveRecord-backed repository — the single data gateway every
  # controller and job talks to (built by Reimbursements.build_store).
  #
  # No cache layer: lists are memoized per instance (one store per request/job
  # run) so repeated reads in one render cost one query.
  #
  # Writers accept an established attribute vocabulary
  # (person_record_id/budget_record_id/batch_id strings, arrays for
  # sharepoint_receipt_urls and linked_*_ids); nil values are dropped so
  # email-in submissions can be created with gaps.
  class DatabaseStore
    # Raised instead of removing an expense's last receipt (drafts excepted).
    class LastReceiptError < StandardError; end

    # Bucket label for budgets with a blank nominal code in the overview.
    NO_CODE_LABEL = "(none)".freeze

    # Attribute-vocabulary translations onto AR columns; everything else in
    # the vocabulary already matches its column name.
    EXPENSE_KEY_MAP = { person_record_id: :person_id, budget_record_id: :budget_id }.freeze
    PERSON_FIELDS = %i[name email].freeze
    PAYMENT_DETAILS_FIELDS = %i[sort_code account_number verified notes].freeze

    def expenses
      @expenses ||= Expense.includes(:person, :budget, :batch)
                           .with_attached_receipt_files.to_a
    end

    # A person's expenses, newest submission first.
    def expenses_for(person_record_id)
      return [] if person_record_id.blank?

      expenses.select { |e| e.person&.record_id == person_record_id }
              .sort_by { |e| e.submitted_at || Time.zone.at(0) }
              .reverse
    end

    def find_expense(record_id)
      Expense.includes(:person, :budget, :batch).find_by(id: record_id)
    end
    alias find_expense! find_expense

    def find_person(record_id)
      Person.includes(:payment_details).find_by(id: record_id)
    end

    def person_by_email(email)
      return nil if email.blank?

      people.find { |p| p.email.to_s.strip.casecmp?(email.strip) }
    end

    def find_budget(record_id)
      Budget.includes(:owners, :forecasts).find_by(id: record_id)
    end

    def find_batch(record_id)
      Batch.find_by(id: record_id)
    end

    def people
      @people ||= Person.includes(:payment_details).to_a
    end

    def budgets
      # eusa_actuals are preloaded both directly (income credits on budget_id)
      # and through expenses (expense debit legs) so the overview's per-line
      # EUSA-actual rollup costs no per-budget queries.
      @budgets ||= Budget.includes(:owners, :forecasts, :eusa_actuals,
                                   expenses: :eusa_actuals).to_a
    end

    # Budgets a submitter may charge an expense to.
    def active_budgets
      budgets.select { |b| b.active && !b.income? }.sort_by(&:name)
    end

    # Budgets grouped by nominal code for the overview page, ordered by code
    # with the blank-code bucket ("(none)") sorted last. Each budget carries its
    # own memoized rollups (preloaded in #budgets), so the grouped totals cost
    # no extra queries.
    def budgets_by_nominal_code
      budgets.group_by { |b| b.nominal_code.presence || NO_CODE_LABEL }
             .sort_by { |code, _| [ code == NO_CODE_LABEL ? 1 : 0, code ] }
             .to_h
    end

    # EUSA actuals booked against a nominal code with no budget at all — real
    # spend against a code no one planned for, surfaced separately on the
    # overview so it isn't lost.
    def unbudgeted_actuals
      coded = budgets.map(&:nominal_code).to_set
      eusa_actuals.reject { |a| coded.include?(a.nominal_code) }
    end

    def update_budget!(record_id, attrs)
      budget = Budget.find(record_id)
      attrs = attrs.compact
      owner_ids = attrs.delete(:owner_ids)
      budget.update!(attrs)
      budget.sync_owner_ids!(Array(owner_ids).reject(&:blank?)) unless owner_ids.nil?
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

    # Retries the auto_number MAX+1 race: two concurrent creates (portal vs
    # poll job) can pick the same number; the unique index rejects the loser,
    # which re-reads MAX on the retry. Explicit auto_numbers (the importer)
    # are never retried — a collision there is real data corruption.
    def create_expense!(attrs)
      attempts = 0
      begin
        expense = Expense.create!(expense_columns(attrs)
                                    .reverse_merge(financial_year: FinancialYear.current))
      rescue ActiveRecord::RecordNotUnique
        raise if attrs.key?(:auto_number) || (attempts += 1) >= 3

        retry
      end
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

    # Refuses to leave a non-draft receipt-less (drafts don't require one).
    # attachment_id is the blob signed id the Attachment wrapper exposes.
    def remove_receipt!(expense_record_id, attachment_id)
      expense = Expense.find(expense_record_id)
      target = expense.receipt_files.find { |file| file.signed_id == attachment_id }
      return bust_expenses! if target.nil?

      raise LastReceiptError if !expense.draft? && expense.receipt_files.one?

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

    # PersonLink's stored user->payee link: the real FK on this backend.
    # update_column deliberately skips validations/callbacks so legacy user
    # records that no longer validate can still use the portal.
    def stored_person_link(user)
      user.reimbursements_person_id&.to_s
    end

    def remember_person_link!(user, person)
      user.update_column(:reimbursements_person_id, person.id) # rubocop:disable Rails/SkipsModelValidations
    end

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

    # Actuals already imported for a given EUSA period (P1..P12), used to dedup
    # a freshly-pasted export against what's already stored for that period.
    def actuals_for_period(period)
      eusa_actuals.select { |a| a.period == period }
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

    # eusa_draft_created is a derived Batch method (from draft_message_id),
    # not a column; BatchProcessor still passes the flag through create_batch!,
    # so it is dropped here rather than raising an unknown-attribute error.
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
