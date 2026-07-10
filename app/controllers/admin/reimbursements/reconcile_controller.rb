module Admin
  module Reimbursements
    ##
    # EUSA actuals reconciliation for the finance team. Ports bedlam-bacs
    # `pages/6_Reconcile.py`: a three-step wizard.
    #
    #   1. show    — paste the monthly EUSA actuals export + a source month.
    #   2. preview — parse (legacy/Sage auto-detect), dedup against rows already
    #                imported for that month, and match debits to Submitted/Paid
    #                expenses and credits to income budgets.
    #   3. apply   — create EUSA Actuals records, link them to the matched
    #                expense/budget, mark matched expenses Paid, and email the
    #                producers "you've been paid".
    #
    # The wizard is stateless: preview/apply re-parse the pasted text carried in
    # the form (the parse + match functions are pure), so nothing is stashed in
    # the session and the dedup on apply always re-checks a fresh actuals list.
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`).
    class ReconcileController < FinanceController
      SOURCE_MONTH_FORMAT = /\A\d{4}-\d{2}\z/

      def show
        @title = "Reconcile EUSA actuals"
      end

      def preview
        @title = "Reconcile EUSA actuals"
        @pasted_text = params[:pasted_text].to_s
        @source_month = params[:source_month].to_s.strip

        return render :show unless valid_source_month?
        return render :show if @pasted_text.strip.empty?

        parsed = parse_rows(@pasted_text)
        return render :show if parsed.nil?

        if parsed.empty?
          flash.now[:alert] = "No data rows found in the pasted text (only a header?)."
          return render :show
        end

        @new_rows, @skipped_rows = dedup(parsed, @source_month)
        @matched_debits, @matched_credits, @unmatched_rows = build_matches(@new_rows)
        render :preview
      end

      def apply
        @source_month = params[:source_month].to_s.strip
        pasted_text = params[:pasted_text].to_s

        unless valid_source_month? && pasted_text.strip.present?
          redirect_to admin_reimbursements_reconciliation_path,
                      alert: "Nothing to apply — start again from the paste step."
          return
        end

        parsed = parse_rows(pasted_text)
        if parsed.nil?
          redirect_to admin_reimbursements_reconciliation_path,
                      alert: "Could not parse the actuals — start again from the paste step."
          return
        end

        new_rows, @skipped_count = dedup(parsed, @source_month).then { |new_r, skipped| [ new_r, skipped.size ] }
        matched_debits, matched_credits, unmatched = build_matches(new_rows)

        apply_reconciliation(matched_debits, matched_credits, unmatched)
        notify_paid_producers(matched_debits)

        @expenses_paid = matched_debits.size
        @credits_linked = matched_credits.size
        @unmatched_saved = unmatched.size
        render :apply
      end

      private

      def valid_source_month?
        if @source_month.match?(SOURCE_MONTH_FORMAT)
          true
        else
          flash.now[:alert] = "Source month must be in YYYY-MM format (e.g. 2026-05)."
          false
        end
      end

      def parse_rows(text)
        ::Reimbursements::Reconciliation.parse_actuals_rows(text, cost_centre_code: cost_centre_code)
      rescue ArgumentError => e
        flash.now[:alert] = "Could not parse actuals: #{e.message}"
        nil
      end

      def cost_centre_code
        ::Reimbursements::CostCentre.default&.eusa_code || "F40"
      end

      # Split freshly-parsed rows into [new, already-imported] using the dedup key
      # against the actuals already stored for this source month.
      def dedup(rows, source_month)
        existing = store.actuals_for_month(source_month).map(&:dedup_key).to_set
        rows.partition do |row|
          key = ::Reimbursements::Reconciliation.actuals_row_dedup_key(
            row.nominal_code, row.narrative, row.debit, row.credit
          )
          !existing.include?(key)
        end
      end

      # Match debits to Submitted/Paid expenses (each claimed at most once) and
      # credits to income budgets. Returns [matched_debits, matched_credits,
      # unmatched] where matched_* are [row, expense|budget] pairs.
      def build_matches(rows)
        remaining = store.expenses.select { |e| matchable_statuses.include?(e.status) }
        income_budgets = store.budgets.select(&:income?)

        matched_debits = []
        matched_credits = []
        unmatched = []

        rows.each do |row|
          if row.debit.positive?
            expense = ::Reimbursements::Reconciliation.match_debit_to_expense(row, remaining)
            if expense
              matched_debits << [ row, expense ]
              remaining.delete(expense)
            else
              unmatched << row
            end
          elsif row.credit.positive?
            budget = ::Reimbursements::Reconciliation.match_credit_to_budget(row, income_budgets)
            budget ? matched_credits << [ row, budget ] : unmatched << row
          else
            unmatched << row
          end
        end

        [ matched_debits, matched_credits, unmatched ]
      end

      def matchable_statuses
        [ ::Reimbursements::Status::SUBMITTED, ::Reimbursements::Status::PAID ]
      end

      def apply_reconciliation(matched_debits, matched_credits, unmatched)
        imported_at = Time.current

        matched_debits.each do |row, expense|
          actual = store.create_actual!(actuals_attrs(row, imported_at))
          store.link_actual_to_expense!(actual.record_id, expense.record_id)
          store.update_expense!(expense.record_id,
                                status: ::Reimbursements::Status::PAID,
                                payment_confirmed_date: row.date)
        end

        matched_credits.each do |row, budget|
          actual = store.create_actual!(actuals_attrs(row, imported_at))
          store.link_actual_to_budget!(actual.record_id, budget.record_id)
        end

        unmatched.each { |row| store.create_actual!(actuals_attrs(row, imported_at)) }
      end

      # One "you've been paid" email per producer, covering all of their newly
      # paid expenses. Producers with no linked person or no email are skipped.
      #
      # Delivered now, not enqueued: the mailer's arguments are Airtable POROs
      # (Person/Expense), which ActiveJob can't serialize for a background job.
      # Apply is already a synchronous, API-heavy operator action, so sending
      # inline here is consistent and keeps the flow simple.
      def notify_paid_producers(matched_debits)
        matched_debits.group_by { |_row, expense| expense.person }.each do |person, pairs|
          next if person.nil? || person.email.blank?

          expenses = pairs.map { |_row, expense| expense }
          ::Reimbursements::PaymentMailer.payment_confirmation(person, expenses).deliver_now
        end
      end

      def actuals_attrs(row, imported_at)
        {
          nominal_code: row.nominal_code, cost_centre: row.cost_centre, ref: row.ref,
          date: row.date, period: row.period, narrative: row.narrative,
          narrative_1: row.narrative_1, debit: row.debit, credit: row.credit, net: row.net,
          source_month: @source_month, imported_at: imported_at
        }
      end
    end
  end
end
