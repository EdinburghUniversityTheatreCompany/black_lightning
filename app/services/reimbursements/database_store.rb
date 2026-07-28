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

    # Raised instead of converting a ledger row that stopped being convertible
    # between the caller's check and the write (see create_expense_for_actual!).
    class NotConvertibleError < StandardError; end

    # Bucket label for budgets with a blank nominal code in the overview.
    NO_CODE_LABEL = "(none)".freeze

    # Attribute-vocabulary translations onto AR columns; everything else in
    # the vocabulary already matches its column name.
    EXPENSE_KEY_MAP = { person_record_id: :person_id, budget_record_id: :budget_id }.freeze
    PERSON_FIELDS = %i[name email].freeze
    # Bank fields route to the linked PaymentDetails record; the vocabulary is defined on
    # that model, next to the columns it names.
    PAYMENT_DETAILS_FIELDS = PaymentDetails::FIELDS

    # The payee's payment_details ride along: every attention/BACS check asks an
    # expense for its EFFECTIVE bank details, which falls through to the linked
    # person, so without this a 150-payee workbook paid 150 extra queries.
    def expenses
      @expenses ||= Expense.includes(:budget, :batch, person: :payment_details)
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

    # Every budget with the owners + forecasts every caller needs. Deliberately
    # WITHOUT the actuals preload: most callers (the producer's budget <select>,
    # the review queue's over-budget check, the nightly job) only want names and
    # forecasts, and pulling the whole expenses + actuals ledger to draw a
    # dropdown costs six queries and the entire expenses table in memory.
    def budgets
      @budgets ||= Budget.includes(:owners, :forecasts).to_a
    end

    # Budgets with their EUSA actuals preloaded, for the two places that show the
    # EUSA-actual rollup: the budgets index/overview and the Budgets export.
    # Actuals are preloaded both directly (income credits on budget_id) and
    # through expenses (expense debit legs), so the per-line rollup costs no
    # per-budget query however many budgets there are.
    def budgets_with_actuals
      @budgets_with_actuals ||= Budget.includes(:owners, :forecasts, :eusa_actuals,
                                                expenses: :eusa_actuals).to_a
    end

    # Budgets a submitter may charge an expense to.
    def active_budgets
      budgets.select { |b| b.active && !b.income? }.sort_by(&:name)
    end

    # Budgets grouped by nominal code for the overview page, ordered by code
    # with the blank-code bucket ("(none)") sorted last. Built from
    # #budgets_with_actuals, since the overview shows the EUSA-actual rollup for
    # every line, so the grouped totals cost no extra queries.
    def budgets_by_nominal_code
      budgets_with_actuals.group_by { |b| b.nominal_code.presence || NO_CODE_LABEL }
             .sort_by { |code, _| [ code == NO_CODE_LABEL ? 1 : 0, code ] }
             .to_h
    end

    # EUSA ledger rows that no budget's figures account for: not linked to an
    # expense (which is how an Expense budget reaches its actuals), not linked
    # to a budget (how an Income budget reaches its credits), and not a leg of
    # an offsetting pair (an accrual and its reversal net to zero, so neither is
    # spend).
    #
    # Deliberately linkage-based rather than nominal-code based. Several budgets
    # can share one nominal code, so a per-budget rollup can only ever count
    # what is actually linked to it; defining this list by code instead would
    # hide an unlinked row behind any budget sharing that code — which is
    # precisely the spend this list exists to surface.
    #
    # Sorted by nominal code, then date, so finance can see which budget each
    # row probably belongs to.
    def unattributed_actuals
      eusa_actuals.reject { |a| a.offset? || a[:expense_id].present? || a[:budget_id].present? }
                  .sort_by { |a| [ a.nominal_code.to_s, a.date || Date.new(0), a.id ] }
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

      BudgetForecast.where(budget_id: budget_id).includes(:budget_update)
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

    # Records a multi-budget revision in one gesture: a BudgetUpdate carrying
    # the shared effective_date + note + author, and one BudgetForecast per
    # entry linked to it (dated with the shared date, its reason set to the
    # shared note). +forecasts+ is an array of {budget_id:, amount:} — the
    # caller drops blank amounts. All-or-nothing: an invalid entry rolls the
    # whole update back.
    def create_budget_update!(effective_date:, note:, created_by:, forecasts:)
      update = nil
      BudgetUpdate.transaction do
        update = BudgetUpdate.create!(effective_date: effective_date, note: note,
                                      created_by: created_by,
                                      financial_year: FinancialYear.current)
        forecasts.each do |entry|
          BudgetForecast.create!(budget_id: entry[:budget_id], amount: entry[:amount],
                                 date: effective_date, reason: note, budget_update: update)
        end
      end
      bust_budgets!
      update
    end

    def budget_updates
      BudgetUpdate.includes(:created_by, :forecasts)
                  .order(effective_date: :desc, id: :desc).to_a
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
      # removable.
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

    def find_actual(record_id)
      EusaActual.includes(:expense, :budget).find_by(id: record_id)
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

    # Turns an unlinked debit row into a From-EUSA expense and links the row to
    # it as ONE unit. Returns the new expense; raises NotConvertibleError if the
    # row is not (or is no longer) convertible.
    #
    # Both halves matter. Creating the expense and linking afterwards as two
    # writes leaves, on a failure between them, a Paid expense charged to a budget
    # while the row stays unlinked and keeps offering its "Create expense" button,
    # so the next click double-counts the same EUSA charge. And the caller's
    # convertibility check is a read that goes stale on a double-submitted form,
    # so it is re-taken here under a row lock: the second writer blocks until the
    # first commits, then sees the link and is refused.
    def create_expense_for_actual!(actual_id, attrs)
      expense = nil
      EusaActual.transaction do
        actual = EusaActual.lock.find(actual_id)
        raise NotConvertibleError unless actual.convertible_to_expense?

        expense = create_expense!(attrs)
        link_actual_to_expense!(actual_id, expense.record_id)
      end
      bust_eusa_actuals!
      expense
    end

    # Imports both legs of an offsetting pair and cross-links them as ONE unit.
    #
    # Two separate create_actual! calls followed by a link leave the worst state
    # available if anything in the middle fails: the debit leg committed WITHOUT
    # the offset stamp, so every rollup reads it as real spend. Re-pasting cannot
    # repair that, because dedup then skips the already-imported leg and the pair
    # can never be re-formed. Returns the two linked legs.
    def create_offsetting_pair!(debit_attrs, credit_attrs)
      legs = EusaActual.transaction do
        debit = create_actual!(debit_attrs)
        credit = create_actual!(credit_attrs)
        link_offsetting_pair!(debit.record_id, credit.record_id)
      end
      bust_eusa_actuals!
      legs
    end

    # The way back out of an offset: both legs lose the stamp and the
    # cross-link and become ordinary ledger rows again. Reachable from either
    # leg, all-or-nothing, and it deletes nothing.
    #
    # The pairing heuristic can be wrong, and being wrong hides real spend from
    # the ledger view and every rollup, so this has to be reversible without a
    # console. Any row pointing AT this one is cleared too, so a half-linked row
    # from an older import can't be left behind.
    def unlink_offsetting_pair!(actual_id)
      legs = EusaActual.transaction do
        actual = EusaActual.lock.find(actual_id)
        counterparts = EusaActual.lock.where(offset_of_id: actual.id).to_a
        counterparts << EusaActual.lock.find_by(id: actual.offset_of_id) if actual.offset_of_id
        [ actual, *counterparts ].compact.uniq.each do |leg|
          leg.update!(offset_of_id: nil, reconciliation_status: nil)
        end
      end
      bust_eusa_actuals!
      legs
    end

    # Records that two imported rows cancel each other out (an accrual and its
    # reversal). Both rows survive — finance needs the audit trail — so each leg
    # is stamped "offset" and pointed at the other. All-or-nothing: a half-
    # stamped pair would show one leg as noise and the other as real spend.
    def link_offsetting_pair!(actual_id, counterpart_id)
      legs = [ EusaActual.find(actual_id), EusaActual.find(counterpart_id) ]
      EusaActual.transaction do
        legs.each_with_index do |leg, index|
          leg.update!(offset_of_id: legs[1 - index].id,
                      reconciliation_status: EusaActual::STATUS_OFFSET)
        end
      end
      bust_eusa_actuals!
      legs
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
      @budgets_with_actuals = nil
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

    def batch_columns(attrs)
      attrs.compact
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
