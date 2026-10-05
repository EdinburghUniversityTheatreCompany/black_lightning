module Admin
  module Reimbursements
    ##
    # The finance team's review queue: three tabs of editable expense cards,
    # with Save, Approve, Reject and the owner sign-off override.
    class ReviewController < FinanceController
      include RejectsExpenses
      include AttachesReceipts

      # ?tab= is the URL state. Links from elsewhere carry no tab, so anything
      # unrecognised lands on the finance queue.
      TABS = %w[awaiting_owner to_approve approved].freeze
      DEFAULT_TAB = "to_approve".freeze

      # Names the edit as the cause, so a refusal it caused does not read as a
      # standing condition.
      GATE_REOPENED_BY_EDIT =
        "Your edit changed the amount or budget, so it needs a fresh owner sign-off.".freeze

      def index
        @title = "Review Expenses"
        @tab = resolve_tab

        # One list feeds every tab, its count and its CSV. The split happens
        # before the format branch because the CSV follows the tab.
        expenses = store.expenses_for_cost_centre
        @pending = expenses.select(&:pending?)
        @owner_gate_unmet_ids = ::Reimbursements::OwnerReview.unmet_gate_expense_ids(@pending)
        queue = ::Reimbursements::ReviewSupport.split_queue(expenses, @owner_gate_unmet_ids)
        @approved = queue[:approved]
        @awaiting_owner = queue[:awaiting_owner]
        @to_approve = queue[:to_approve]

        respond_to do |format|
          format.html { load_queue }
          format.csv { send_export ::Reimbursements::Exports::Expenses, expenses_for_tab }
        end
      end

      def save
        expense = save_edits(find_queue_expense!) or return

        notice = "Saved changes to ##{expense.auto_number}."
        notice += " #{GATE_REOPENED_BY_EDIT}" if @gate_reopened_by_edit
        redirect_to_review(notice: notice)
      end

      def approve
        expense = save_edits_if_asked(find_queue_expense!) or return
        redirect_with_approve_result(expense, approve_expense(expense))
      end

      # Finance override of the owner sign-off gate. Every other blocker still refuses.
      def override_approve
        expense = save_edits_if_asked(find_queue_expense!) or return
        result = override_one(expense, params[:override_note])
        note = "Approved ##{expense.auto_number} (owner sign-off overridden)." if @override_written
        redirect_with_approve_result(expense, result, approved_notice: note)
      end

      # Override the owner gate on every ticked claim. The note is required here,
      # though optional on one claim: it is the only record that finance bypassed
      # a control on several claims at once.
      def bulk_override_approve
        note = params[:override_note].to_s.strip
        if note.blank?
          return redirect_to_review(alert: "Say why you're overriding sign-off before doing it " \
                                           "in bulk. It's the only record of the decision.")
        end

        expenses = selected_pending_expenses
        return redirect_to_review(alert: "Select at least one claim to override.") if expenses.empty?

        results = expenses.map { |expense| override_one(expense, note) }
        redirect_to_review(notice: bulk_override_summary(results))
      end

      def reject
        expense = save_edits_if_asked(find_queue_expense!) or return
        reason = params[:rejection_reason].to_s.strip
        if reason.blank?
          redirect_to_review(alert: "A rejection reason is required.")
          return
        end

        if reject_expense(expense, reason) == :skipped_wrong_status
          redirect_to_review(alert: "##{expense.auto_number} can no longer be rejected (already #{expense.status}).")
        else
          redirect_to_review(notice: "Rejected ##{expense.auto_number}.")
        end
      end

      def bulk_approve
        expenses = selected_pending_expenses
        return redirect_to_review(alert: "Select at least one expense to approve.") if expenses.empty?

        results = expenses.map { |expense| approve_expense(expense) }
        redirect_to_review(notice: bulk_approve_summary(results))
      end

      def bulk_reject
        reason = params[:rejection_reason].to_s.strip
        return redirect_to_review(alert: "A rejection reason is required.") if reason.blank?

        expenses = selected_pending_expenses
        return redirect_to_review(alert: "Select at least one expense to reject.") if expenses.empty?

        emailed = expenses.count { |e| reject_expense(e, reason) == true }
        redirect_to_review(notice: bulk_reject_summary(expenses.size, emailed))
      end

      def add_receipts
        expense = find_queue_expense!
        attached, upload_errors = attach_posted_receipts(expense)
        if attached.zero?
          redirect_to_review(alert: upload_errors.presence&.to_sentence ||
                                    NOTHING_USABLE)
          return
        end

        redirect_to_review(notice: "Attached #{attached} receipt(s) to ##{expense.auto_number}.",
                           alert: upload_errors.presence&.to_sentence)
      rescue StandardError => e # AR/ActiveStorage failures
        redirect_to_review(alert: "Couldn't attach the receipt: #{e.message}")
      end

      def remove_receipt
        expense = find_queue_expense!
        store.remove_receipt!(expense.record_id, params[:attachment_id])
        redirect_to_review(notice: "Removed a receipt from ##{expense.auto_number}.")
      rescue ::Reimbursements::DatabaseStore::LastReceiptError
        redirect_to_review(alert: "Can't remove the last receipt from a submitted expense.")
      rescue StandardError => e
        redirect_to_review(alert: "Couldn't remove the receipt: #{e.message}")
      end

      private

      # find_expense!, noting the claim's place on its tab. Read BEFORE the
      # action, which may take the card off the tab.
      def find_queue_expense!
        expense = find_expense!
        @anchor_record_id = expense.record_id
        @anchor_successors = successors_on_tab(expense)
        expense
      end

      # The record ids rendering AFTER this claim on its tab, nearest first.
      def successors_on_tab(expense)
        order = rendered_tab_order
        index = order.index(expense.record_id)
        index ? order[(index + 1)..] : []
      end

      # The tab's record ids in render order (To approve is Ready, then Needs
      # attention). Read before and after an action, so the anchor follows the
      # queue as it now stands.
      def rendered_tab_order
        expenses = store.expenses_for_cost_centre
        pending = expenses.select(&:pending?)
        unmet = ::Reimbursements::OwnerReview.unmet_gate_expense_ids(pending)
        queue = ::Reimbursements::ReviewSupport.split_queue(expenses, unmet)

        case resolve_tab
        when "approved" then queue[:approved]
        when "awaiting_owner" then queue[:awaiting_owner]
        else ordered_to_approve(queue[:to_approve], pending)
        end.map(&:record_id)
      end

      def ordered_to_approve(to_approve, pending)
        ready, attention = ::Reimbursements::ReviewSupport.partition_ready(
          to_approve, store.budgets.index_by(&:record_id), modulus_checker,
          ::Reimbursements::ReviewSupport.find_duplicate_submissions(pending)
        )
        ready + attention
      end

      # The claim acted on if it is still on this tab, else the nearest one that
      # rendered below it. nil (the top of the list) when none survived, or
      # after a bulk action.
      def queue_anchor
        return nil if @anchor_record_id.blank?

        remaining = rendered_tab_order
        target =
          if remaining.include?(@anchor_record_id)
            @anchor_record_id
          else
            @anchor_successors.find { |id| remaining.include?(id) }
          end
        target && "expense-#{target}"
      end

      def expenses_for_tab
        case @tab
        when "approved" then @approved
        when "awaiting_owner" then @awaiting_owner
        else @to_approve
        end
      end

      def resolve_tab
        tab = params[:tab].to_s
        TABS.include?(tab) ? tab : DEFAULT_TAB
      end

      # Everything only the on-screen queue needs.
      def load_queue
        @budgets = store.active_budgets
        @budget_by_id = store.budgets.index_by(&:record_id)
        @duplicates = ::Reimbursements::ReviewSupport.find_duplicate_submissions(@pending)
        # Over the approved claims too, or the "overridden" pill vanishes the
        # moment the override succeeds.
        @endorsements_by_expense =
          store.endorsements_by_expense((@pending + @approved).map(&:record_id))
        @people_by_id = store.people.index_by(&:record_id)
        # A possible duplicate counts as attention here only: the scan is per
        # pending list, so it is not one of the shared needs_attention_reasons.
        @ready, @attention = ::Reimbursements::ReviewSupport.partition_ready(
          @to_approve, @budget_by_id, modulus_checker, @duplicates
        )
      end

      def redirect_with_approve_result(expense, result, approved_notice: nil)
        case result
        when :skipped_no_bank
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without bank details.")
        when :skipped_wrong_status
          redirect_to_review(alert: "##{expense.auto_number} is no longer Pending, so there is nothing to approve.")
        when :skipped_no_budget
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without a budget linked. " \
                                    "It would write a blank nominal code EUSA can never reconcile.")
        when :skipped_no_amount
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without an amount " \
                                    "excluding VAT. It would never match on reconciliation.")
        when :skipped_no_foreign_amount
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without the amount in EUR. " \
                                    "That is the figure EUSA's international payment form asks for.")
        when :skipped_no_gbp_amount
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without a GBP amount. " \
                                    "Enter what the payment is expected to cost in pounds. The budget " \
                                    "counts it in GBP, and reconciliation corrects it to the rate the " \
                                    "bank charged.")
        when :skipped_awaiting_endorsement
          alert = "##{expense.auto_number} needs a budget owner's endorsement first " \
                  "(or a finance override)."
          alert = "#{GATE_REOPENED_BY_EDIT} #{alert}" if @gate_reopened_by_edit
          redirect_to_review(alert: alert)
        else
          redirect_to_review(notice: approved_notice || "Approved ##{expense.auto_number}.")
        end
      end

      # Approve unless approve_blocker refuses; fills a BACS-safe payment
      # reference when blank. Returns :approved or the blocker.
      def approve_expense(expense)
        blocker = approve_blocker(expense)
        return blocker if blocker

        attrs = { status: ::Reimbursements::Status::APPROVED }
        # display_name, not the bare name: three shows' "Marketing" lines would
        # share one reference, and EUSA reconciles payments by it. A stored
        # reference is never recomputed.
        if expense.payment_reference.to_s.strip.empty?
          reference = ::Reimbursements::ReviewSupport.auto_payment_reference(expense.budget.display_name)
          attrs[:payment_reference] = reference if reference.present?
        end
        store.update_expense!(expense.record_id, attrs)
        :approved
      end

      # The first reason this expense can't be approved, or nil. Writes nothing.
      def approve_blocker(expense)
        return :skipped_wrong_status unless expense.pending?
        return :skipped_no_bank unless expense.effective_has_bank_details?
        # A blank budget writes a blank nominal code into the BACS spreadsheet,
        # which EUSA can never reconcile.
        return :skipped_no_budget if expense.budget.nil? || expense.budget.record_id.blank?
        # The international pair goes before the ex-VAT guard: ex-VAT mirrors the
        # gross on that rail, so a blank GBP amount fails both, and the ex-VAT
        # message names a field the rail lacks.
        return :skipped_no_foreign_amount if ::Reimbursements::ReviewSupport.missing_foreign_amount?(expense)
        return :skipped_no_gbp_amount if ::Reimbursements::ReviewSupport.missing_gbp_amount?(expense)
        return :skipped_no_amount if expense.amount_excl_vat.nil? || expense.amount_excl_vat.zero?
        return :skipped_awaiting_endorsement unless ::Reimbursements::OwnerReview.gate_satisfied?(expense)

        nil
      end

      # Overrides the gate and approves. Never writes the override row while a
      # hard block remains: a later plain approve would sail past it. Upserted,
      # so a re-override after an edit refreshes the snapshot.
      def override_one(expense, note)
        blocker = approve_blocker(expense)
        return blocker if blocker && blocker != :skipped_awaiting_endorsement

        if ::Reimbursements::OwnerReview.gate_applies?(expense)
          ::Reimbursements::OwnerEndorsement.for_expense(expense.record_id).first_or_initialize.update!(
            budget_record_id: expense.budget.record_id,
            endorsed_by_person_id: nil,
            overridden_by: current_user,
            note: note.to_s.truncate(255).presence,
            endorsed_amount: expense.amount,
            endorsed_at: Time.current
          )
          @override_written = true
        end
        approve_expense(expense)
      rescue ActiveRecord::RecordNotUnique
        # An owner endorsed a moment ago; the gate is satisfied, so just approve.
        approve_expense(expense)
      end

      # Skips are named as data problems: the gate is what this action just
      # cleared, so naming it would read as the override failing.
      def bulk_override_summary(results)
        approved = results.count(:approved)
        skipped = results.size - approved
        parts = [ "#{approved} approved with sign-off overridden" ]
        parts << "#{skipped} skipped (missing bank details, budget, or amount)" if skipped.positive?
        "#{parts.join(', ')}."
      end

      # Filtered to Pending, never trusting the posted ids, so a stale selection
      # can't act on a claim already decided.
      def selected_pending_expenses
        ids = Array(params[:expense_ids]).compact_blank
        return [] if ids.empty?

        store.expenses.select { |e| e.pending? && ids.include?(e.record_id) }
      end

      # Owner-gate skips are counted apart from data-problem skips.
      def bulk_approve_summary(results)
        approved = results.count(:approved)
        awaiting = results.count(:skipped_awaiting_endorsement)
        other = results.count { |r| r != :approved && r != :skipped_awaiting_endorsement }
        parts = [ "#{approved} approved" ]
        parts << "#{awaiting} awaiting owner sign-off" if awaiting.positive?
        parts << "#{other} skipped (missing bank details, budget, or amount)" if other.positive?
        "#{parts.join(', ')}."
      end

      def bulk_reject_summary(rejected, emailed)
        "#{rejected} rejected, #{emailed} producer#{'s' unless emailed == 1} emailed."
      end

      # Save Changes in the unsaved-edits dialog sends the card's edits with the decision.
      def save_edits_if_asked(expense) = params[:save_changes].present? ? save_edits(expense) : expense

      # Invalid edits redirect and return nil, so edits and a decision stand or fall together.
      def save_edits(expense)
        error = ::Reimbursements::AmountValidation.error_for(
          amount: params[:amount], amount_excl_vat: params[:amount_excl_vat]
        ) || budget_record_id_error(params[:budget_record_id])
        if error
          redirect_to_review(alert: error)
          return nil
        end

        apply_edits(expense)
      end

      # Writes the card's edits, noting whether that re-opened a covering owner
      # endorsement (editing the amount or budget revokes it).
      def apply_edits(expense)
        was_endorsed = ::Reimbursements::OwnerReview.gate_applies?(expense) &&
                       ::Reimbursements::OwnerReview.gate_satisfied?(expense)
        updated = store.update_expense!(expense.record_id, save_attrs)
        @gate_reopened_by_edit =
          was_endorsed && !::Reimbursements::OwnerReview.gate_satisfied?(updated)
        updated
      end

      def save_attrs
        attrs = {
          # The parsed BigDecimal, not the raw field: AR casts "£1,200" to 0.
          amount: ::Reimbursements::AmountValidation.amount(params[:amount]),
          description: params[:description],
          payment_reference: params[:payment_reference],
          nominal_code_override: params[:nominal_code_override].to_s,
          budget_record_id: params[:budget_record_id].presence
        }
        # An excl-VAT of 0 means "not yet known": leave the field alone.
        excl_vat = ::Reimbursements::AmountValidation.amount_excl_vat(params[:amount_excl_vat])
        attrs[:amount_excl_vat] = excl_vat if excl_vat
        attrs
      end

      # Back to the tab and card acted on. params[:tab] is passed through
      # verbatim, not resolve_tab'd, so no tab stays no tab.
      def redirect_to_review(flash)
        target = queue_anchor
        # BOTH ?focus= and the fragment: Turbo's fetch follows the 302 itself and
        # drops the fragment, so scroll_to_controller reads focus. A no-JS
        # navigation honours the fragment.
        redirect_to admin_reimbursements_review_path(tab: params[:tab], focus: target,
                                                     anchor: target),
                    **flash
      end
    end
  end
end
