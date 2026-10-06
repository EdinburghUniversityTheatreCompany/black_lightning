module Admin
  module Reimbursements
    class BankDetailsComponentPreview < ViewComponent::Preview
      def default
        render BankDetailsComponent.new(sort_code: "08-99-99", account_number: "66374958",
                                        payee: "Pat Producer")
      end

      def no_details_on_file
        render BankDetailsComponent.new(sort_code: "", account_number: "")
      end

      # Only half the details made it in.
      def partial_details
        render BankDetailsComponent.new(sort_code: "08-99-99", account_number: "",
                                        payee: "Acme Lighting Hire")
      end
    end
  end
end
