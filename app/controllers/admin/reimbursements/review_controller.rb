module Admin
  module Reimbursements
    ##
    # The finance team's review queue. Ports bedlam-bacs `pages/2_Review.py`:
    # Pending / Approved tabs, editable expense cards, an AI check kicked off per
    # unchecked Pending expense on load (a background job, so the request isn't
    # blocked), a modulus badge on the EFFECTIVE payee details, payee-override
    # and duplicate-submission warnings, and a needs-attention partition.
    #
    # Actions: Save (write edits), Approve (auto-fill a BACS-safe payment
    # reference if blank, block without effective bank details), Reject (reason
    # required, send the rejection email, stamp rejection_notified).
    #
    # Gated by the finance grid permission (`:manage, :reimbursements_finance`)
    # via FinanceController.
    class ReviewController < FinanceController
      include RejectsExpenses

      def index
        @title = "Review Expenses"
        @tab = params[:tab] == "approved" ? "approved" : "pending"

        expenses = store.expenses
        @pending = expenses.select(&:pending?)
        @approved = expenses.select { |e| e.status == ::Reimbursements::Status::APPROVED }

        kick_ai_checks(@pending)

        @budgets = store.active_budgets
        @budget_by_id = store.budgets.index_by(&:record_id)
        @duplicates = ::Reimbursements::ReviewSupport.find_duplicate_submissions(@pending)
        # partition: ready first (needs_attention false, no possible duplicate),
        # attention second. A possible duplicate is folded in here (not into the
        # shared needs_attention_reasons, which other callers use for expenses
        # this per-pending-list duplicate scan was never computed for) so it's
        # grouped with every other advisory reason instead of being a wholly
        # separate, easy-to-miss warning box.
        # Which pending expenses still await a budget owner's endorsement (batched
        # to avoid an N+1). A blocking gate: finance can't approve until an owner
        # endorses or overrides.
        @owner_gate_unmet_ids = ::Reimbursements::OwnerReview.unmet_gate_expense_ids(@pending)
        # For the positive "Endorsed by / Cleared by finance" chip on the card,
        # and to resolve the endorsing owner's name.
        @endorsements_by_expense = ::Reimbursements::OwnerEndorsement
          .where(expense_record_id: @pending.map(&:record_id)).index_by(&:expense_record_id)
        @people_by_id = store.people.index_by(&:record_id)
        @ready, @attention = @pending.partition do |expense|
          !::Reimbursements::ReviewSupport.needs_attention(expense, @budget_by_id, modulus_checker) &&
            !@duplicates.key?(expense.record_id) &&
            !@owner_gate_unmet_ids.include?(expense.record_id)
        end
      end

      def save
        expense = find_expense!
        error = ::Reimbursements::AmountValidation.error_for(
          amount: params[:amount], amount_excl_vat: params[:amount_excl_vat]
        ) || budget_record_id_error(params[:budget_record_id])
        if error
          redirect_to_review(alert: error)
          return
        end

        # A covering owner endorsement before the edit means this Save may have
        # re-opened the gate (if it changed amount/budget) — tell finance so the
        # claim jumping back to "awaiting sign-off" isn't a surprise. update_expense!
        # returns the updated claim, so no extra Airtable read.
        was_endorsed = ::Reimbursements::OwnerReview.gate_applies?(expense) &&
                       ::Reimbursements::OwnerReview.gate_satisfied?(expense)
        updated = store.update_expense!(expense.record_id, save_attrs)

        notice = "Saved changes to ##{expense.auto_number}."
        notice += " Your edit changed the amount or budget, so it needs a fresh owner sign-off." \
          if was_endorsed && !::Reimbursements::OwnerReview.gate_satisfied?(updated)
        redirect_to_review(notice: notice)
      end

      def approve
        expense = find_expense!
        redirect_with_approve_result(expense, approve_expense(expense))
      end

      # Finance override of the owner-endorsement gate: record who overrode it
      # (e.g. no owner has a portal account to endorse), then approve. Only the
      # owner gate can be overridden this way — every other blocking reason is a
      # genuine data problem the override still can't approve past.
      def override_approve
        expense = find_expense!
        # Only override the owner gate when it's the ONLY thing blocking. If a
        # hard block (bank/budget/amount/status) remains, report that WITHOUT
        # writing an override row — otherwise a later plain approve would sail
        # past a gate we silently satisfied here for an approval that never ran.
        blocker = approve_blocker(expense)
        if blocker && blocker != :skipped_awaiting_endorsement
          redirect_with_approve_result(expense, blocker)
          return
        end

        if ::Reimbursements::OwnerReview.gate_applies?(expense)
          # Upsert so a re-override after an edit refreshes the snapshot (see
          # OwnerReview.endorsement_covers?), rather than riding a stale row.
          endorsement = ::Reimbursements::OwnerEndorsement.for_expense(expense.record_id).first_or_initialize
          endorsement.assign_attributes(
            budget_record_id: expense.budget.record_id,
            endorsed_by_person_id: nil,
            overridden_by: current_user,
            note: params[:override_note].to_s.truncate(255).presence,
            endorsed_amount: expense.amount,
            endorsed_at: Time.current
          )
          endorsement.save!
        end
        result = approve_expense(expense)
        note = result == :approved ? "Approved ##{expense.auto_number} (owner sign-off overridden)." : nil
        redirect_with_approve_result(expense, result, approved_notice: note)
      rescue ActiveRecord::RecordNotUnique
        # An owner endorsed a moment ago; the gate is satisfied, so just approve.
        redirect_with_approve_result(expense, approve_expense(expense))
      end

      def reject
        expense = find_expense!
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

      # Approve every selected Pending expense in one go, reusing the single
      # approve path per item (same bank-details block + BACS-reference auto-fill).
      # Reports a per-item summary in the flash.
      def bulk_approve
        expenses = selected_pending_expenses
        return redirect_to_review(alert: "Select at least one expense to approve.") if expenses.empty?

        results = expenses.map { |expense| approve_expense(expense) }
        redirect_to_review(notice: bulk_approve_summary(results))
      end

      # Reject every selected Pending expense with one shared reason, reusing the
      # single reject path per item (each producer is emailed via Graph).
      def bulk_reject
        reason = params[:rejection_reason].to_s.strip
        return redirect_to_review(alert: "A rejection reason is required.") if reason.blank?

        expenses = selected_pending_expenses
        return redirect_to_review(alert: "Select at least one expense to reject.") if expenses.empty?

        emailed = expenses.count { |e| reject_expense(e, reason) == true }
        redirect_to_review(notice: bulk_reject_summary(expenses.size, emailed))
      end

      def add_receipts
        expense = find_expense!
        files = Array(params[:receipts]).compact_blank.select do |file|
          file.size <= ::Reimbursements::ExpenseForm::MAX_RECEIPT_BYTES &&
            ::Reimbursements::ReceiptContentType.allowed_upload?(file)
        end
        if files.empty?
          redirect_to_review(alert: "No usable receipt files (PDF or image, under the size limit).")
          return
        end

        files.each do |file|
          store.attach_receipt!(expense.record_id, filename: file.original_filename,
                                                   content_type: file.content_type, bytes: file.read)
        end
        redirect_to_review(notice: "Attached #{files.size} receipt(s) to ##{expense.auto_number}.")
      rescue StandardError => e # any backend: Airtable::Error, AR/ActiveStorage failures
        redirect_to_review(alert: "Couldn't attach the receipt: #{e.message}")
      end

      def remove_receipt
        expense = find_expense!
        store.remove_receipt!(expense.record_id, params[:attachment_id])
        redirect_to_review(notice: "Removed a receipt from ##{expense.auto_number}.")
      rescue ::Reimbursements::Store::LastReceiptError
        redirect_to_review(alert: "Can't remove the last receipt from a submitted expense.")
      rescue StandardError => e
        redirect_to_review(alert: "Couldn't remove the receipt: #{e.message}")
      end

      private

      # Map an approve_expense result to the redirect + flash, shared by #approve
      # and #override_approve so their messaging never drifts.
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
        when :skipped_awaiting_endorsement
          redirect_to_review(alert: "##{expense.auto_number} needs a budget owner's endorsement first " \
                                    "(or a finance override).")
        else
          redirect_to_review(notice: approved_notice || "Approved ##{expense.auto_number}.")
        end
      end

      # Approve one expense (shared by #approve and #bulk_approve). Blocks a
      # stale/raced approval against an expense that's no longer Pending
      # (:skipped_wrong_status — e.g. a double-click, or a concurrent Build
      # Batch/reconciliation already advanced it), one with no effective bank
      # details (:skipped_no_bank), no linked budget (:skipped_no_budget — a
      # blank budget writes a blank nominal code straight into the BACS
      # spreadsheet, permanently breaking reconciliation matching), or no
      # non-zero ex-VAT amount (:skipped_no_amount — the reconciliation
      # matcher can never match a nil/zero amount, so the expense is paid but
      # never marked Paid). The other "needs attention" reasons (no receipt,
      # possible duplicate) stay advisory-only — the operator's own judgement
      # call, not a correctness guard. Auto-fills a BACS-safe payment
      # reference when blank. Returns :approved on success.
      def approve_expense(expense)
        blocker = approve_blocker(expense)
        return blocker if blocker

        attrs = { status: ::Reimbursements::Status::APPROVED }
        # expense.budget is already guaranteed present here (approve_blocker's
        # :skipped_no_budget guard returns early otherwise), so no nil re-check.
        if expense.payment_reference.to_s.strip.empty?
          reference = ::Reimbursements::ReviewSupport.auto_payment_reference(expense.budget.name)
          attrs[:payment_reference] = reference if reference.present?
        end
        store.update_expense!(expense.record_id, attrs)
        :approved
      end

      # The first reason this expense can't be approved, or nil if it can. Pure
      # (no writes), so override_approve can precheck whether the owner gate is
      # the SOLE blocker before recording an override — a hard block (bank/
      # budget/amount) must never write a gate-satisfying override row.
      def approve_blocker(expense)
        return :skipped_wrong_status unless expense.pending?
        return :skipped_no_bank unless expense.effective_has_bank_details?
        # A present-but-blank-record_id budget would write a blank nominal code
        # into the BACS spreadsheet just like a nil one — guard both, so this
        # stays in lockstep with ReviewSupport.attention_summary's "no budget"
        # blocking reason (the UI promises the two agree).
        return :skipped_no_budget if expense.budget.nil? || expense.budget.record_id.blank?
        return :skipped_no_amount if expense.amount_excl_vat.nil? || expense.amount_excl_vat.zero?
        # A budget owner must sign off before finance approves (any one owner, or
        # a submitter who owns the budget is auto-bypassed). Overridable by
        # finance via override_approve; unmet here means neither has happened.
        return :skipped_awaiting_endorsement unless ::Reimbursements::OwnerReview.gate_satisfied?(expense)

        nil
      end

      # The Pending expenses ticked in the bulk toolbar. Filtering to Pending
      # (never trusting the posted ids alone) keeps a stale selection from acting
      # on an already-approved/rejected expense.
      def selected_pending_expenses
        ids = Array(params[:expense_ids]).compact_blank
        return [] if ids.empty?

        store.expenses.select { |e| e.pending? && ids.include?(e.record_id) }
      end

      # Names the owner-gate skips separately from the data-problem skips so
      # finance isn't told a gated claim was "missing bank/budget/amount".
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

      # ai_checked? (not ai_check_status.present?) so an "error" verdict — the
      # checker itself couldn't run, not a real pass/fail — gets retried the
      # next time Review loads, rather than being stuck forever the moment a
      # transient Gemini outage clears.
      def kick_ai_checks(expenses)
        expenses.reject(&:ai_checked?).each do |expense|
          ::Reimbursements::AiCheckJob.perform_later(expense.record_id)
        end
      end

      def save_attrs
        attrs = {
          amount: params[:amount].presence,
          description: params[:description],
          payment_reference: params[:payment_reference],
          nominal_code_override: params[:nominal_code_override].to_s,
          budget_record_id: params[:budget_record_id].presence
        }
        # Only write excl-VAT when a positive value is given, mirroring Review.py
        # (0 means "not yet known", leave the field alone).
        excl_vat = params[:amount_excl_vat].to_f
        attrs[:amount_excl_vat] = excl_vat if excl_vat.positive?
        attrs
      end

      def redirect_to_review(flash)
        redirect_to admin_reimbursements_review_path(tab: params[:tab]), **flash
      end
    end
  end
end
