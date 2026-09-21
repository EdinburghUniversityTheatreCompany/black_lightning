module Admin
  module Reimbursements
    ##
    # An area's budget lines, each with the same four figures as the headline
    # block above, plus its income lines in a table of their own.
    #
    # **Income is never totalled with spend** — the standing rule in this
    # portal — so an income line cannot be a row here: its "budget" is money to
    # RAISE, and a Left column that subtracted claims from it would be counting
    # the wrong way round. Income gets expected-against-received instead, which
    # is the only pair of figures that means anything on that side.
    class BudgetLinesComponent < ViewComponent::Base
      # A component gets no helpers of its own, and these two are how every
      # money figure and date in this portal is written.
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

      # A one-line area whose line carries the area's own name (the median
      # shape in production: "Tech" inside "Tech") would print the word twice
      # for no information, so the table says so once in its heading instead.
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
