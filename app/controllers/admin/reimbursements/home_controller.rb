module Admin
  module Reimbursements
    ##
    # The portal's front door: finance gets this dashboard, anyone else is sent
    # to their own claims. So the finance gate cannot be a before_action: a
    # producer must reach this URL.
    class HomeController < FinanceController
      # FinanceController already skipped the base portal gate, so the gate here
      # is the union of the two permissions (neither implies the other).
      skip_before_action :authorize_finance!
      before_action :authorize_front_door!

      def show
        return redirect_to(admin_reimbursements_expenses_path) unless finance?

        @title = "Finance home"
        @home = ::Reimbursements::FinanceHome.new(store: store, cost_centre: selected_cost_centre)
      end

      private

      def authorize_front_door!
        return if can?(:access, :reimbursements) || finance?

        authorize! :access, :reimbursements
      end

      def finance?
        can?(:manage, :reimbursements_finance)
      end
    end
  end
end
