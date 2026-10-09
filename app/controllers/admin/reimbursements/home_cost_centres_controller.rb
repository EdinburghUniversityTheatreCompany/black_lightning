module Admin
  module Reimbursements
    ##
    # Sets or clears the signed-in finance user's home cost centre, which the
    # sidebar and the import wizards use as a default. It changes no bare URL:
    # with no ?cost_centre= a finance screen still shows every centre.
    #
    # update_column: a preference must not be vetoed by an unrelated User
    # validation, nor file a PaperTrail version or run User's callbacks.
    class HomeCostCentresController < FinanceController
      def update
        unless selected_cost_centre
          return redirect_back_or_to(admin_reimbursements_root_path, alert: "Choose a cost centre first.")
        end

        current_user.update_column(:reimbursements_cost_centre_id, selected_cost_centre.id)
        redirect_back_or_to admin_reimbursements_root_path,
                            notice: "#{selected_cost_centre.name} is now your default cost centre."
      end

      def destroy
        current_user.update_column(:reimbursements_cost_centre_id, nil)
        redirect_back_or_to admin_reimbursements_root_path, notice: "Default cost centre cleared."
      end
    end
  end
end
