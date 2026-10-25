module Admin
  module Reimbursements
    ##
    # An area's budget lines with the headline block's four figures, plus its
    # income lines apart. Income is never totalled with spend: its budget is
    # money to RAISE, so income lines get expected-against-received instead.
    class BudgetLinesComponent < ViewComponent::Base
      # A component gets no helpers of its own.
      delegate :reimbursements_money, to: :helpers

      def initialize(lines:, income_lines:, finance:, area: nil)
        @lines = lines
        @income_lines = income_lines
        @finance = finance
        @area = area
      end

      private

      attr_reader :lines, :income_lines, :area

      def finance? = @finance

      # A one-line area whose line has the area's own name ("Tech" in "Tech",
      # the median shape) says so once, in the heading.
      def single_line_named_after_area?
        lines.one? && income_lines.empty? && lines.first.name.to_s.strip == area&.name.to_s.strip
      end

      def heading = single_line_named_after_area? ? "Its one budget" : "Budgets"

      def summary_for(line) = ::Reimbursements::SpendSummary.for_budget(line)

      # Both tables' headings as [text, classes]: Name, finance's Nominal code, then the table's
      # right-aligned money columns.
      def head_columns(*money_columns)
        columns = [ [ "Name", "px-3 py-2" ] ]
        columns << [ "Nominal code", "px-3 py-2" ] if finance?
        columns + money_columns.map { |text| [ text, "px-3 py-2 text-right" ] }
      end
    end
  end
end
