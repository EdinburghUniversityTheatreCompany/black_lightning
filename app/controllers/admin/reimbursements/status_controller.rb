module Admin
  module Reimbursements
    ##
    # Health dashboard for the reimbursements integrations: the last nightly run
    # per cost centre, the send log, and a Microsoft Graph probe that runs on
    # demand (#run), never on page load.
    class StatusController < FinanceController
      before_action :load_cost_centres

      def show
      end

      def run
        @checks = [ graph_check ]
        respond_to do |format|
          format.turbo_stream
          format.html { render :show }
        end
      end

      private

      # A run-day or two of reminders; the recipient search reaches further back.
      SEND_LOG_LIMIT = 50

      def load_cost_centres
        @title = "Integration Status"
        @cost_centres = ::Reimbursements::CostCentre.order(:name)
        load_send_log
      end

      # ?recipient= searches one address: "did this person get their reminder?"
      def load_send_log
        @recipient_query = params[:recipient].to_s.strip
        logs = ::Reimbursements::NotificationLog.recent(
          limit: SEND_LOG_LIMIT, cost_centre: (selected_cost_centre if @recipient_query.blank?)
        )
        logs = logs.for_recipient(@recipient_query) if @recipient_query.present?
        @sends = logs.to_a
        # One line per day and kind: a run-day sends one kind to several people,
        # and the count is what looks wrong when it is wrong.
        @send_counts = @sends.group_by { |log| [ log.sent_at.to_date, log.kind ] }
                             .transform_values(&:size)
                             .sort_by(&:first).reverse
        # Printed, so an empty stretch reads as before the log, not a quiet week.
        @send_log_since = ::Reimbursements::NotificationLog.minimum(:sent_at)
        @send_log_limit = SEND_LOG_LIMIT
      end

      # Acquire an app-only Graph token (see GraphClient#check_reachable). Rescues
      # its own failure, so a dead service renders a failed row rather than a 500.
      def graph_check
        unless ::Reimbursements::Settings.mailbox_configured?
          return Check.new(label: "Microsoft Graph", status: :skip, detail: "No Azure credentials configured yet.")
        end

        graph.check_reachable
        Check.new(label: "Microsoft Graph", status: :ok, detail: "Reachable: acquired an app token.")
      rescue StandardError => e
        Check.new(label: "Microsoft Graph", status: :fail,
                  detail: "#{e.message}. The Azure app's client secret may have expired. Contact IT " \
                          "to rotate it (it's a server credential, not set here).")
      end
    end
  end
end
