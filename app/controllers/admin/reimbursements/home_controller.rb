module Admin
  module Reimbursements
    ##
    # The portal's front door, at /admin/reimbursements itself.
    #
    # This URL used to redirect EVERYBODY to the producer's own claim list, so
    # the business manager opening the portal was greeted with "Submit your
    # expenses here" — the single reason a newcomer could not find the job.
    # It now answers each audience with its own landing: a finance user gets
    # this dashboard, and anyone else is sent on to their claims exactly as
    # before.
    #
    # So the finance permission CANNOT be a before_action here. A producer has
    # access to the portal and must reach its front door; 403ing them at the
    # URL the sidebar's "My Claims" resolves under would be a regression on
    # what a plain redirect did. The branch is in #show instead.
    class HomeController < FinanceController
      # FinanceController has already SKIPPED the base portal gate to put the
      # finance one in its place, so skipping THAT alone left this URL behind
      # nothing but :access, :backend — the one URL every audience lands on
      # first, and the only one in the namespace behind no portal permission.
      #
      # Neither permission implies the other (a Business Manager is granted
      # reimbursements_finance and not access/reimbursements), so the gate is
      # their UNION and #show branches inside it.
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
