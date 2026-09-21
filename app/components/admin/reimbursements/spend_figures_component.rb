module Admin
  module Reimbursements
    ##
    # The four figures at the top of an area page or a loose line's page:
    # Budget, Spent, Waiting for approval, Left — with a bar underneath.
    #
    # The words are the ones a producer uses, and the portal's own term for
    # each sits under it in small type FOR FINANCE ONLY. An owner reading
    # "committed" under "Spent" learns nothing; a finance user reading it can
    # tell at a glance which of the fifteen money labels in this portal the
    # figure above is, and so whether it should match the budgets index.
    class SpendFiguresComponent < ViewComponent::Base
      # A component gets no helpers of its own, and these two are how every
      # money figure and date in this portal is written.
      delegate :reimbursements_money, :reimbursements_date, to: :helpers

      # The finance term under each plain label. Not a glossary — just enough
      # for a finance user to map the word to the column they know.
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

      # Where the comparator came from. An area with no agreed total still has
      # a figure to measure against — what its lines add up to — but calling
      # that "the budget" without saying so presents a sum nobody agreed as a
      # decision somebody made.
      def budget_note
        return "nobody has set one" if summary.no_budget_set?
        return "no total agreed; what its lines add up to" if summary.from_lines?

        finance? ? "agreed total" : nil
      end

      def term(key) = finance? ? FINANCE_TERMS[key] : nil

      # An area's agreed total that has not all been handed to a line. Read
      # straight off the area so this can never disagree with the figure the
      # area edit card prints for the same area.
      def unallocated = summary.unallocated

      def show_unallocated? = area.present? && !unallocated.nil?
    end
  end
end
