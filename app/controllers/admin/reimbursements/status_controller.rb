module Admin
  module Reimbursements
    ##
    # Health dashboard for the reimbursements emails: the last nightly run and the
    # notification recipients per cost centre, and the send log.
    class StatusController < FinanceController
      def show
        @title = "Integration Status"
        @cost_centres = ::Reimbursements::CostCentre.order(:name)
        load_send_log
      end

      private

      # A run-day or two of reminders; the recipient search reaches further back.
      SEND_LOG_LIMIT = 50

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
    end
  end
end
