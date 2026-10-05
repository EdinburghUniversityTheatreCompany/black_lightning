module Admin
  module Reimbursements
    ##
    # Health dashboard for the reimbursements integrations: the last nightly run
    # per cost centre, the send log, and a Microsoft Graph probe that runs on
    # demand (#run), never on page load.
    class StatusController < FinanceController
      # Injection seam for tests: the app-only Graph client (token probe).
      class_attribute :graph_builder, default: -> { ::Reimbursements::GraphClient.new }

      # One row of the integration-check results.
      Check = Struct.new(:label, :status, :detail, keyword_init: true)

      before_action :load_cost_centres

      def show
      end

      def run
        @checks = run_checks
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
        @sends =
          if @recipient_query.present?
            ::Reimbursements::NotificationLog.for_recipient(@recipient_query)
                                             .recent_first.includes(:cost_centre)
                                             .limit(SEND_LOG_LIMIT).to_a
          else
            ::Reimbursements::NotificationLog.recent(limit: SEND_LOG_LIMIT,
                                                     cost_centre: selected_cost_centre).to_a
          end
        # One line per day and kind: a run-day sends one kind to several people,
        # and the count is what looks wrong when it is wrong.
        @send_counts = @sends.group_by { |log| [ log.sent_at.to_date, log.kind ] }
                             .transform_values(&:size)
                             .sort_by { |(date, kind), _| [ date, kind ] }.reverse
        # Printed, so an empty stretch reads as before the log, not a quiet week.
        @send_log_since = ::Reimbursements::NotificationLog.minimum(:sent_at)
        @send_log_limit = SEND_LOG_LIMIT
      end

      def graph
        @graph ||= graph_builder.call
      end

      # Each probe rescues its own failure, so a dead service renders a failed
      # row rather than a 500.
      def run_checks
        [ graph_check ]
      end

      # Acquire an app-only Graph token (see GraphClient#check_reachable).
      def graph_check
        return graph_skip unless ::Reimbursements::Settings.mailbox_configured?

        graph.check_reachable
        Check.new(label: "Microsoft Graph", status: :ok, detail: "Reachable: acquired an app token.")
      rescue StandardError => e
        Check.new(label: "Microsoft Graph", status: :fail,
                  detail: "#{e.message}. The Azure app's client secret may have expired. Contact IT " \
                          "to rotate it (it's a server credential, not set here).")
      end

      def graph_skip
        Check.new(label: "Microsoft Graph", status: :skip,
                  detail: "No Azure credentials configured yet.")
      end
    end
  end
end
