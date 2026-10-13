module Admin
  module Reimbursements
    ##
    # The figures at the top of an area page or a loose line's page, with a bar underneath.
    # Finance also sees the portal's own term for each figure in small type, to map the
    # plain word to the column they know.
    class SpendFiguresComponent < ViewComponent::Base
      # Components get no helpers of their own.
      delegate :reimbursements_money, to: :helpers

      FINANCE_TERMS = {
        spent: "committed: approved, with EUSA or paid",
        waiting: "pipeline: claims still to approve",
        left: "budget less spent and waiting"
      }.freeze

      def initialize(summary:, finance:, area: nil)
        @summary = summary
        @finance = finance
        @area = area
      end

      private

      attr_reader :summary, :area

      def finance? = @finance

      # A sum of lines must not be presented as an agreed total.
      def budget_note
        return "nobody has set one" if summary.no_budget_set?
        return "no total agreed; what its lines add up to" if summary.from_lines?

        finance? ? "agreed total" : nil
      end

      def term(key) = finance? ? FINANCE_TERMS[key] : nil

      def show_unallocated? = area.present? && !summary.unallocated.nil?
    end
  end
end
