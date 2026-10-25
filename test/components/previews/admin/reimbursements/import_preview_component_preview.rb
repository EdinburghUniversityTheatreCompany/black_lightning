module Admin
  module Reimbursements
    # The top of an import wizard's preview step. The step's own buckets are stood in for by a line
    # of text.
    class ImportPreviewComponentPreview < ViewComponent::Preview
      def default
        render ImportPreviewComponent.new(back_path: "#", alert: nil, financial_year: year,
                                          cost_centre: centre, invalid_verb: "read", errors: []) do
          "The sheet's new and changed budgets are listed here."
        end
      end

      # Apply refused the sheet: the alert, each unusable row, and a whole-sheet error.
      def nothing_can_be_imported
        render ImportPreviewComponent.new(
          back_path: "#", alert: "Nothing was imported. Fix the rows flagged below and try again.",
          financial_year: year, cost_centre: centre, invalid_verb: "imported",
          errors: [ "The sheet has no Date submitted column." ]
        ) do |preview|
          preview.with_invalid_row { "OLD-2: \"about a ton\" isn't an amount." }
          preview.with_invalid_row { "OLD-3: nobody on the People screen has the email sam@example.com." }
        end
      end

      private

      def year = ::Reimbursements::FinancialYear.new(key: "fringe-2027", label: "Fringe 2027")

      def centre = ::Reimbursements::CostCentre.new(id: 1, key: "fringe", name: "Bedlam Fringe")
    end
  end
end
