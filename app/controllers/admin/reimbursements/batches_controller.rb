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

      # Injection seam for tests (this suite has no mocking library): the Graph
      # client used to delete a reopened batch's stale EUSA draft.
      class_attribute :graph_builder, default: -> { ::Reimbursements::GraphClient.new }

      def index
        @title = "Batch history"
        @batches = store.batches.sort_by { |batch| batch.date_sent || Date.new(0) }.reverse
        @expenses_by_batch = processed_expenses.group_by(&:batch_id)
      end

      def show
        @batch = store.find_batch(params[:id])
        raise ActiveRecord::RecordNotFound if @batch.nil?

        @expenses = processed_expenses.select { |expense| expense.batch_id == @batch.record_id }
      end

      def new
        @title = "Build batch"
        @expenses = approved_expenses
        @total = total(@expenses)
        @bacs_date = Date.current
        @sender_name = default_sender
        @eusa_recipient = @cost_centre.eusa_recipient_or_default
        @default_email = compose_default_email(@bacs_date, @sender_name)
      end

      # Enqueue the build (BuildBatchJob serialises per cost centre, so a
      # double-click can't double-submit) and send the operator to History; the
      # draft link lands there and in their inbox when the background run finishes.
      def create
        ::Reimbursements::BuildBatchJob.perform_later(
          cost_centre_key: @cost_centre.key,
          bacs_date: parsed_bacs_date.iso8601,
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
        batch = store.find_batch(params[:id])
        raise ActiveRecord::RecordNotFound if batch.nil?

        linked = processed_expenses.select { |expense| expense.batch_id == batch.record_id }
        paid = linked.select { |expense| expense.status == ::Reimbursements::Status::PAID }
        return blocked_by_paid(paid) if paid.any?

        linked.each { |expense| store.revert_expense_to_approved!(expense.record_id) }
        store.delete_batch!(batch.record_id)

        reverted = "Reverted #{linked.size} #{'expense'.pluralize(linked.size)} to Approved and removed the batch."
        redirect_to admin_reimbursements_batches_path, **draft_cleanup_flash(batch, reverted)
      end

      private

      # Delete the stale EUSA draft this batch created, then build the reopen
      # flash. The revert + batch delete have already happened and must stand, so
      # a Graph failure is rescued (best-effort): the reopen still succeeds, with
      # a warning telling the operator to delete the draft by hand. Falls back to
      # the same manual warning when the batch has no stored draft id.
      def draft_cleanup_flash(batch, reverted)
        if batch.draft_message_id.present?
          begin
            graph_builder.call.delete_message(mailbox: draft_mailbox, message_id: batch.draft_message_id)
            return { notice: "#{reverted} The old EUSA draft in Outlook has been deleted." }
          rescue StandardError => e
            Rails.logger.error("Reopen: failed to delete EUSA draft #{batch.draft_message_id} — #{e.message}")
            Honeybadger.notify(e, context: { source: "reimbursements_reopen_draft_delete", batch: batch.record_id })
          end
        end

        { notice: reverted,
          alert: "Delete the old EUSA draft in Outlook manually before sending the rebuilt one." }
      end

      def draft_mailbox
        ::Reimbursements::CostCentre.default&.send_mailbox
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

      def parsed_bacs_date
        Date.parse(params[:bacs_date].to_s)
      rescue ArgumentError
        Date.current
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
