module Admin
  module Reimbursements
    ##
    # An area's budget lines with the headline block's four figures, plus its
    # income lines apart. Income is never totalled with spend: its budget is
    # money to RAISE, so income lines get expected-against-received instead.
    class BudgetLinesComponent < ViewComponent::Base
      # A component gets no helpers of its own.
      delegate :reimbursements_money, :reimbursements_date, to: :helpers

      def initialize(lines:, income_lines:, finance:, area: nil)
        @lines = lines
        @income_lines = income_lines
        @finance = finance
        @area = area
      end

      private

      attr_reader :lines, :income_lines, :area

      def finance? = @finance

      def any? = lines.any? || income_lines.any?

      # A one-line area whose line has the area's own name ("Tech" in "Tech",
      # the median shape) says so once, in the heading.
      def single_line_named_after_area?
        lines.one? && income_lines.empty? && lines.first.name.to_s.strip == area&.name.to_s.strip
      end

      def heading
        return "Its one line" if single_line_named_after_area?

        "Lines"
      end

      def summary_for(line) = ::Reimbursements::SpendSummary.for_budget(line)

      # What an income line was expected to raise, and what EUSA's ledger says
      # actually landed against it.
      def income_expected(line) = line.no_budget_set? ? nil : line.projected_amount

      def income_received(line) = line.eusa_actual_amount
    end
  end
end
