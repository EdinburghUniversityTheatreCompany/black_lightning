module Admin
  module Reimbursements
    ##
    # Clearing a build-attempt banner from History once it has been dealt with.
    #
    # Dismissing only hides the alert. The row keeps its status, its errors and
    # its batch_record_id, so the audit trail of what was attempted is intact.
    class BatchAttemptsController < FinanceController
      def dismiss
        attempt = ::Reimbursements::BatchAttempt.find(params[:id])

        unless attempt.dismissable?
          return redirect_to(admin_reimbursements_batches_path,
                             alert: "That build is still running. Wait for it to finish.")
        end

        attempt.dismiss!(email: current_user&.email)
        redirect_to admin_reimbursements_batches_path, notice: "Alert dismissed."
      end
    end
  end
end
