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
      # Injection seam for tests: the modulus checker (from the vendored Pay.UK
      # rule files in production; a fake in functional tests).
      class_attribute :checker_builder, default: -> { ::Reimbursements::ModulusCheck.default_checker }

      # Injection seam for tests: the Graph-backed email notifier, sending the
      # rejection email from the cost centre's send mailbox.
      class_attribute :notifier_builder,
                      default: ->(mailbox:) { ::Reimbursements::Notifier.new(mailbox: mailbox) }

      helper_method :modulus_checker

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
        @ready, @attention = @pending.partition do |expense|
          !::Reimbursements::ReviewSupport.needs_attention(expense, @budget_by_id, modulus_checker) &&
            !@duplicates.key?(expense.record_id)
        end
      end

      def save
        expense = find_expense!
        error = ::Reimbursements::AmountValidation.error_for(
          amount: params[:amount], amount_excl_vat: params[:amount_excl_vat]
        )
        if error
          redirect_to_review(alert: error)
          return
        end

        store.update_expense!(expense.record_id, save_attrs)
        redirect_to_review(notice: "Saved changes to ##{expense.auto_number}.")
      end

      def approve
        expense = find_expense!
        case approve_expense(expense)
        when :skipped_no_bank
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without bank details.")
        when :skipped_wrong_status
          redirect_to_review(alert: "##{expense.auto_number} is no longer Pending — nothing to approve.")
        when :skipped_no_budget
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without a budget linked — " \
                                    "it would write a blank nominal code EUSA can never reconcile.")
        when :skipped_no_amount
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without an amount " \
                                    "excluding VAT — it would never match on reconciliation.")
        else
          redirect_to_review(notice: "Approved ##{expense.auto_number}.")
        end
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

        approved, skipped = expenses.partition { |e| approve_expense(e) == :approved }
        redirect_to_review(notice: bulk_approve_summary(approved.size, skipped.size))
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
      rescue ::Reimbursements::Airtable::Error => e
        redirect_to_review(alert: "Couldn't attach the receipt: #{e.message}")
      end

      def remove_receipt
        expense = find_expense!
        store.remove_receipt!(expense.record_id, params[:attachment_id])
        redirect_to_review(notice: "Removed a receipt from ##{expense.auto_number}.")
      rescue ::Reimbursements::Store::LastReceiptError
        redirect_to_review(alert: "Can't remove the last receipt from a submitted expense.")
      rescue ::Reimbursements::Airtable::Error => e
        redirect_to_review(alert: "Couldn't remove the receipt: #{e.message}")
      end

      private

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
        return :skipped_wrong_status unless expense.pending?
        return :skipped_no_bank unless expense.effective_has_bank_details?
        return :skipped_no_budget if expense.budget.nil?
        return :skipped_no_amount if expense.amount_excl_vat.nil? || expense.amount_excl_vat.zero?

        attrs = { status: ::Reimbursements::Status::APPROVED }
        if expense.payment_reference.to_s.strip.empty? && expense.budget
          reference = ::Reimbursements::ReviewSupport.auto_payment_reference(expense.budget.name)
          attrs[:payment_reference] = reference if reference.present?
        end
        store.update_expense!(expense.record_id, attrs)
        :approved
      end

      # Reject one expense with a reason (shared by #reject and #bulk_reject).
      # Blocks a stale/raced rejection against an expense that's no longer
      # Pending or Approved (:skipped_wrong_status) — the guard lives here,
      # not just in #reject, so any future caller gets the same protection
      # #approve_expense already gives #approve/#bulk_approve, rather than
      # depending on the caller to pre-filter (bulk_reject's own filter to
      # Pending only happens to make this unreachable there today). Otherwise
      # notifies the payee, but never blocks the rejection on the send: a
      # missing email or a Graph failure is skipped gracefully (no stamp) so
      # the operator follows up. Returns true when the producer was emailed,
      # false when it wasn't (rejected either way).
      def reject_expense(expense, reason)
        return :skipped_wrong_status unless expense.pending? || expense.approved?

        attrs = { status: ::Reimbursements::Status::REJECTED, rejection_reason: reason }
        notified = notify_rejection(expense, reason)
        attrs[:rejection_notified] = Time.current if notified
        store.update_expense!(expense.record_id, attrs)
        notified
      end

      # The Pending expenses ticked in the bulk toolbar. Filtering to Pending
      # (never trusting the posted ids alone) keeps a stale selection from acting
      # on an already-approved/rejected expense.
      def selected_pending_expenses
        ids = Array(params[:expense_ids]).compact_blank
        return [] if ids.empty?

        store.expenses.select { |e| e.pending? && ids.include?(e.record_id) }
      end

      def bulk_approve_summary(approved, skipped)
        parts = [ "#{approved} approved" ]
        parts << "#{skipped} skipped (missing bank details, budget, or amount)" if skipped.positive?
        "#{parts.join(', ')}."
      end

      def bulk_reject_summary(rejected, emailed)
        "#{rejected} rejected, #{emailed} producer#{'s' unless emailed == 1} emailed."
      end

      def modulus_checker
        @modulus_checker ||= checker_builder.call
      end

      def notifier
        @notifier ||= notifier_builder.call(mailbox: ::Reimbursements::CostCentre.default&.send_mailbox)
      end

      def find_expense!
        expense = store.find_expense!(params[:id])
        raise ActiveRecord::RecordNotFound if expense.nil?

        expense
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

      # Send the rejection via Graph (from the cost centre's send mailbox), but
      # never let a send failure block the rejection itself: a failed send just
      # returns false so the caller leaves rejection_notified unstamped and the
      # operator follows up.
      def notify_rejection(expense, reason)
        email = expense.person&.email
        return false if email.blank?

        notifier.rejection(
          to: email,
          payee_name: expense.person.name,
          auto_number: expense.auto_number,
          amount: expense.amount.to_f,
          budget_name: expense.budget&.name.to_s,
          description: expense.description.to_s,
          reason: reason
        )
        true
      rescue StandardError => e
        Rails.logger.error("Reimbursements: rejection email failed for ##{expense.auto_number} — #{e.message}")
        Honeybadger.notify(e, context: { source: "reimbursements_rejection_email", expense: expense.auto_number })
        false
      end

      def redirect_to_review(flash)
        redirect_to admin_reimbursements_review_path(tab: params[:tab]), **flash
      end
    end
  end
end
