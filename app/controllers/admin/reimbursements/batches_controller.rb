module Admin
  module Reimbursements
    ##
    # Finance-team Build Batch + History, porting bedlam-bacs
    # pages/3_Build_Batch.py and pages/4_History.py.
    #
    # * new / create — preview every Approved expense via its EFFECTIVE payee
    #   (flagging "→ third party" overrides), set the BACS date / EUSA recipient
    #   / signature and edit the EUSA email, then run BatchProcessor: it creates
    #   the draft in the cost centre's send mailbox, offloads receipts + the
    #   xlsx to SharePoint, records the Batch and marks the expenses Submitted.
    # * index / show — past batches with per-batch totals and links.
    # * reopen — revert a batch's expenses to Approved and delete it so it can be
    #   rebuilt; blocked if any expense is already Paid (reconciled).
    #
    # Build Batch runs the processor inline so the operator immediately sees the
    # draft link + metrics; it's structured as a service so the nightly job
    # (Phase F) can run the same flow in the background.
    class BatchesController < FinanceController
      # Injection seam for tests: the app-only Graph client (drafts + SharePoint).
      class_attribute :graph_builder, default: -> { ::Reimbursements::GraphClient.new }

      before_action :require_cost_centre, only: %i[new create]

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

      def create
        @result = ::Reimbursements::BatchProcessor
                  .new(store: store, graph: graph, cost_centre: @cost_centre)
                  .process(
                    expenses: approved_expenses,
                    bacs_date: parsed_bacs_date,
                    sender_name: params[:sender_name].presence || default_sender,
                    eusa_recipient: params[:eusa_recipient].presence || @cost_centre.eusa_recipient_or_default,
                    eusa_subject: params[:eusa_subject],
                    eusa_body_html: params[:eusa_body]
                  )
      end

      def reopen
        batch = store.find_batch(params[:id])
        raise ActiveRecord::RecordNotFound if batch.nil?

        linked = processed_expenses.select { |expense| expense.batch_id == batch.record_id }
        paid = linked.select { |expense| expense.status == ::Reimbursements::Status::PAID }
        return blocked_by_paid(paid) if paid.any?

        linked.each { |expense| store.revert_expense_to_approved!(expense.record_id) }
        store.delete_batch!(batch.record_id)
        redirect_to admin_reimbursements_batches_path,
                    notice: "Reverted #{linked.size} #{'expense'.pluralize(linked.size)} to Approved and " \
                            "removed the batch. The old EUSA draft in Outlook is now outdated — delete it " \
                            "manually before sending the rebuilt one."
      end

      private

      def graph
        @graph ||= graph_builder.call
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
