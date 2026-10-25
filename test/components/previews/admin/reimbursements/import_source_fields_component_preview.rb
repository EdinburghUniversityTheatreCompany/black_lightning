module Admin
  module Reimbursements
    # Step 1's fields in the budget and expense imports, over unpersisted years and centres.
    class ImportSourceFieldsComponentPreview < ViewComponent::Preview
      # Several centres and none named: the operator must choose one.
      def default
        render ImportSourceFieldsComponent.new(
          financial_years: years, financial_year: years.last, cost_centres: centres, cost_centre: nil,
          pasted_text: nil, placeholder: ::Reimbursements::BudgetImport::TSV_HEADERS.join("\t")
        )
      end

      # Reached from a centre's link, or re-rendered after a refusal with the paste kept.
      def centre_chosen_and_sheet_pasted
        render ImportSourceFieldsComponent.new(
          financial_years: years, financial_year: years.first, cost_centres: centres,
          cost_centre: centres.last, pasted_text: "ID\tStatus\nOLD-1\tPaid",
          placeholder: ::Reimbursements::ExpenseImport::TSV_HEADERS.join("\t")
        )
      end

      private

      def years
        [ ::Reimbursements::FinancialYear.new(key: "fringe-2026", label: "Fringe 2026"),
          ::Reimbursements::FinancialYear.new(key: "fringe-2027", label: "Fringe 2027") ]
      end

      def centres
        [ ::Reimbursements::CostCentre.new(id: 1, key: "fringe", name: "Bedlam Fringe"),
          ::Reimbursements::CostCentre.new(id: 2, key: "termtime", name: "Termtime Payments") ]
      end
    end
  end
end
