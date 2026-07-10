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
        # partition: ready first (needs_attention false), attention second.
        @ready, @attention = @pending.partition do |expense|
          !::Reimbursements::ReviewSupport.needs_attention(expense, @budget_by_id, modulus_checker)
        end
      end

      def save
        expense = find_expense!
        store.update_expense!(expense.record_id, save_attrs)
        redirect_to_review(notice: "Saved changes to ##{expense.auto_number}.")
      end

      def approve
        expense = find_expense!
        unless expense.effective_has_bank_details?
          redirect_to_review(alert: "Can't approve ##{expense.auto_number} without bank details.")
          return
        end

        attrs = { status: ::Reimbursements::Status::APPROVED }
        if expense.payment_reference.to_s.strip.empty? && expense.budget
          reference = ::Reimbursements::ReviewSupport.auto_payment_reference(expense.budget.name)
          attrs[:payment_reference] = reference if reference.present?
        end
        store.update_expense!(expense.record_id, attrs)
        redirect_to_review(notice: "Approved ##{expense.auto_number}.")
      end

      def reject
        expense = find_expense!
        reason = params[:rejection_reason].to_s.strip
        if reason.blank?
          redirect_to_review(alert: "A rejection reason is required.")
          return
        end

        attrs = { status: ::Reimbursements::Status::REJECTED, rejection_reason: reason }
        # Notify the payee, but never block the rejection on it. A missing email
        # is skipped gracefully (no stamp) so the operator knows to follow up.
        if notify_rejection(expense, reason)
          attrs[:rejection_notified] = Time.current
        end
        store.update_expense!(expense.record_id, attrs)
        redirect_to_review(notice: "Rejected ##{expense.auto_number}.")
      end

      def add_receipts
        expense = find_expense!
        files = Array(params[:receipts]).compact_blank.select do |file|
          ::Reimbursements::ExpenseForm::ALLOWED_RECEIPT_TYPES.include?(file.content_type) &&
            file.size <= ::Reimbursements::ExpenseForm::MAX_RECEIPT_BYTES
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

      def modulus_checker
        @modulus_checker ||= checker_builder.call
      end

      def find_expense!
        expense = store.find_expense!(params[:id])
        raise ActiveRecord::RecordNotFound if expense.nil?

        expense
      end

      def kick_ai_checks(expenses)
        expenses.reject { |e| e.ai_check_status.present? }.each do |expense|
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

      def notify_rejection(expense, reason)
        email = expense.person&.email
        return false if email.blank?

        ::Reimbursements::ExpenseMailer.rejection_email(
          email: email,
          payee_name: expense.person.name,
          auto_number: expense.auto_number,
          amount: expense.amount.to_f,
          budget_name: expense.budget&.name.to_s,
          description: expense.description.to_s,
          reason: reason
        ).deliver_later
        true
      end

      def redirect_to_review(flash)
        redirect_to admin_reimbursements_review_path(tab: params[:tab]), **flash
      end
    end
  end
end
