module Admin
  module Reimbursements
    ##
    # A submitter's payee name + bank details (their Airtable People record).
    class PaymentDetailsController < BaseController
      def edit
        @title = "My Payment Details"
        @form = ::Reimbursements::PaymentDetailsForm.new(
          name: current_person&.name.presence || current_user.full_name,
          sort_code: current_person&.sort_code,
          account_number: current_person&.account_number
        )
      end

      def update
        @form = ::Reimbursements::PaymentDetailsForm.new(form_params)
        unless @form.valid?
          @title = "My Payment Details"
          render :edit, status: :unprocessable_entity
          return
        end

        person = person_link.ensure_person!(current_user)
        store.update_person!(person.record_id,
                             name: @form.name,
                             sort_code: @form.formatted_sort_code,
                             account_number: @form.normalized_account_number)
        redirect_to admin_reimbursements_expenses_path, notice: "Payment details saved."
      end

      private

      def form_params
        params.require(:reimbursements_payment_details_form).permit(:name, :sort_code, :account_number)
      end
    end
  end
end
