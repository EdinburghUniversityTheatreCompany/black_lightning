module Admin
  module Reimbursements
    ##
    # Finance-team Build Batch + History, porting bedlam-bacs
    # pages/3_Build_Batch.py and pages/4_History.py.
    #
    # * new / create — preview every Approved expense via its EFFECTIVE payee
    #   (flagging "→ third party" overrides), set the BACS date / EUSA recipient
    #   / signature and edit the EUSA email, then enqueue BuildBatchJob, which
    #   creates the draft in the cost centre's send mailbox, offloads receipts +
    #   the xlsx to SharePoint, records the Batch and marks the expenses Submitted.
    # * index / show — past batches with per-batch totals and links.
    # * reopen — revert a batch's expenses to Approved and delete it so it can be
    #   rebuilt; blocked if any expense is already Paid (reconciled).
    #
    # Build Batch runs in the BACKGROUND (BuildBatchJob): the processor is
    # API-heavy (SharePoint uploads + Graph draft) and can exceed the request
    # timeout, and a concurrency lock on the cost centre stops a double-click
    # double-submitting. The operator is redirected to History and emailed the
    # draft link when it's ready.
    class BatchesController < FinanceController
      before_action :require_cost_centre, only: %i[new create]

      def index
        @title = "Batch history"
        @batches = store.batches.sort_by { |batch| batch.date_sent || Date.new(0) }.reverse
        @expenses_by_batch = processed_expenses.group_by(&:batch_id)
      end

      def show
        @batch = find_or_404(:find_batch)
        @expenses = processed_expenses.select { |expense| expense.batch_id == @batch.record_id }
      end

      def new
        assign_new_form
      end

      # Enqueue the build (BuildBatchJob serialises per cost centre, so a
      # double-click can't double-submit) and send the operator to History; the
      # draft link lands there and in their inbox when the background run finishes.
      #
      # The BACS date is validated BEFORE enqueuing: a blank/malformed date must
      # not silently fall back to today (a wrong payment date), so re-render the
      # form with an error and enqueue nothing.
      def create
        bacs_date = parse_bacs_date(params[:bacs_date])
        if bacs_date.nil?
          assign_new_form
          flash.now[:alert] = "Enter a valid BACS date (YYYY-MM-DD) before building the batch."
          return render :new, status: :unprocessable_entity
        end

        if invalid_eusa_recipient?
          assign_new_form
          flash.now[:alert] = "Enter a valid EUSA recipient email address before building the batch."
          return render :new, status: :unprocessable_entity
        end

        ::Reimbursements::BuildBatchJob.perform_later(
          cost_centre_key: @cost_centre.key,
          bacs_date: bacs_date.iso8601,
          sender_name: params[:sender_name].presence || default_sender,
          eusa_recipient: params[:eusa_recipient].presence || @cost_centre.eusa_recipient_or_default,
          eusa_subject: params[:eusa_subject].presence,
          eusa_body_html: params[:eusa_body].presence,
          operator_emails: Array(current_user.try(:email)).compact_blank
        )
        redirect_to admin_reimbursements_batches_path,
                    notice: "Batch is building for #{@cost_centre.name}. Its EUSA draft link will appear " \
                            "here and be emailed to you when ready — don't rebuild it in the meantime."
      end

      def reopen
        batch = find_or_404(:find_batch)
        linked = processed_expenses.select { |expense| expense.batch_id == batch.record_id }
        paid = linked.select { |expense| expense.status == ::Reimbursements::Status::PAID }
        return blocked_by_paid(paid) if paid.any?
        return blocked_by_unconfirmed_draft if batch.draft_message_id.present? && !confirmed_still_draft?(batch)

        linked.each { |expense| store.revert_expense_to_approved!(expense.record_id) }
        store.delete_batch!(batch.record_id)

        reverted = "Reverted #{linked.size} #{'expense'.pluralize(linked.size)} to Approved and removed the batch."
        redirect_to admin_reimbursements_batches_path, **draft_cleanup_flash(batch, reverted)
      end

      private

      def assign_new_form
        @title = "Build batch"
        @expenses = approved_expenses
        @total = total(@expenses)
        @bacs_date = Date.current
        @sender_name = default_sender
        @eusa_recipient = @cost_centre.eusa_recipient_or_default
        @default_email = compose_default_email(@bacs_date, @sender_name)
      end

      # Delete the stale EUSA draft this batch created, then build the reopen
      # flash. The revert + batch delete have already happened and must stand, so
      # a Graph failure is rescued (best-effort): the reopen still succeeds, with
      # a warning telling the operator to delete the draft by hand. Falls back to
      # the same manual warning when the batch has no stored draft id.
      def draft_cleanup_flash(batch, reverted)
        if batch.draft_message_id.present?
          begin
            graph.delete_message(mailbox: draft_mailbox, message_id: batch.draft_message_id)
            return { notice: "#{reverted} The old EUSA draft in Outlook has been deleted." }
          rescue StandardError => e
            log_and_notify("Reopen: failed to delete EUSA draft #{batch.draft_message_id} — #{e.message}", e,
                           context: { source: "reimbursements_reopen_draft_delete", batch: batch.record_id })
          end
        end

        { notice: reverted,
          alert: "Delete the old EUSA draft in Outlook manually before sending the rebuilt one." }
      end

      def draft_mailbox
        ::Reimbursements::CostCentre.default&.send_mailbox
      end

      # Reopen must never revert expenses out of a batch whose EUSA draft was
      # already sent — the whole point of "reopen" is to safely rebuild, and a
      # sent draft means the money is already committed. This app has no
      # visibility into the manual "send in Outlook" step by design, so the
      # only way to tell is asking Graph whether the stored message id is
      # still an unsent draft right now.
      def confirmed_still_draft?(batch)
        graph.draft_message?(mailbox: draft_mailbox, message_id: batch.draft_message_id)
      end

      def blocked_by_unconfirmed_draft
        redirect_to admin_reimbursements_batches_path,
                    alert: "Can't reopen: the EUSA draft for this batch could not be confirmed as " \
                           "still unsent in Outlook (it may already have been sent, or Graph couldn't " \
                           "be reached). If it was genuinely sent, do not reopen — repair reconciliation " \
                           "manually instead of rebuilding."
      end

      def require_cost_centre
        @cost_centre = ::Reimbursements::CostCentre.default
        return if @cost_centre

        redirect_to admin_reimbursements_batches_path,
                    alert: "No cost centre configured. Seed one before building a batch."
      end

      def approved_expenses
        store.expenses.select { |expense| expense.status == ::Reimbursements::Status::APPROVED }
      end

      # Submitted + Paid expenses carry a batch link; these populate History.
      def processed_expenses
        store.expenses.select { |expense| expense.batch_id.present? }
      end

      def total(expenses)
        expenses.sum { |expense| expense.amount || 0 }
      end

      # Parse the submitted BACS date, or nil if it's blank/malformed — the
      # caller re-renders the form rather than silently defaulting to today.
      def parse_bacs_date(value)
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # The form's EUSA recipient is free text overriding the cost centre's
      # own (format-validated) configured recipient, passed straight through
      # as the sole "to" address of the EUSA draft — it gets no format check
      # of its own otherwise. Blank is fine (falls back to the cost centre's
      # recipient); only a non-blank, malformed value is rejected.
      def invalid_eusa_recipient?
        params[:eusa_recipient].present? && !params[:eusa_recipient].match?(URI::MailTo::EMAIL_REGEXP)
      end

      def default_sender
        current_user.try(:full_name).presence || "Bedlam Fringe Finance"
      end

      def compose_default_email(bacs_date, sender_name)
        ::Reimbursements::EusaEmailComposer.new.compose(
          expenses: approved_expenses, bacs_date: bacs_date, sender_name: sender_name,
          eusa_code: @cost_centre.eusa_code
        )
      end

      def blocked_by_paid(paid)
        numbers = paid.map { |expense| "##{expense.auto_number}" }.join(", ")
        redirect_to admin_reimbursements_batches_path,
                    alert: "Can't reopen: #{paid.size} #{'expense'.pluralize(paid.size)} already Paid " \
                           "(#{numbers}). Reconciled payments must not be reverted."
      end
    end
  end
end
