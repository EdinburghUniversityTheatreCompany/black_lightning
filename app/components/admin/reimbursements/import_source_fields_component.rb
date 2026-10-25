module Admin
  module Reimbursements
    ##
    # Step 1's fields in the budget and expense imports: the financial year and cost centre the
    # sheet goes into, and the paste box or .xlsx upload. Field names are what
    # ReadsImportSource reads, so both wizards must keep them.
    class ImportSourceFieldsComponent < ViewComponent::Base
      # A component gets no helpers of its own.
      delegate :input_classes, to: :helpers

      # +cost_centre+ is the preselected centre: the link's, the sole one, or the operator's
      # home centre, never a guess. +placeholder+ shows the sheet's columns in the paste box.
      def initialize(financial_years:, financial_year:, cost_centres:, cost_centre:, pasted_text:,
                     placeholder:)
        @financial_years = financial_years
        @financial_year = financial_year
        @cost_centres = cost_centres
        @cost_centre = cost_centre
        @pasted_text = pasted_text
        @placeholder = placeholder
      end
    end
  end
end
