module Admin
  module Reimbursements
    ##
    # Clearing a build-attempt banner from History once it has been dealt with.
    # Dismissing hides the alert and nothing else.
    class BatchAttemptsController < FinanceController
      def dismiss
        attempt = ::Reimbursements::BatchAttempt.find(params[:id])

        unless attempt.dismissible?
          return redirect_to(admin_reimbursements_batches_path,
                             alert: "That build is still running. Wait for it to finish.")
        end

        attempt.dismiss!(email: current_user&.email)
        redirect_to admin_reimbursements_batches_path, notice: "Alert dismissed."
      end
    end
  end
end
