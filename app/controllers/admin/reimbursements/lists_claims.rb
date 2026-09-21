module Admin
  module Reimbursements
    ##
    # The claims table an area's page and a loose line's page both render: the
    # same list, the same tabs and the same page size, from one definition, so
    # the two screens cannot drift apart (and jscpd's duplication gate stays at
    # zero over two controllers that would otherwise carry the same four lines).
    module ListsClaims
      extend ActiveSupport::Concern

      # Shorter than the finance lists' 50. A claims table is read for "where
      # has mine got to", which is answered near the top, and the busiest
      # production area carries 59 rows.
      CLAIMS_PAGE_SIZE = 25

      private

      # Claims charged to any of these lines, newest first. Read off the store's
      # one preloaded expense list (batch, budget, person and receipts ride
      # along) rather than a query per line.
      def claims_for_lines(lines)
        ids = Array(lines).map(&:record_id).to_set
        store.expenses
             .select { |expense| ids.include?(expense.budget&.record_id) }
             .sort_by { |expense| [ expense.submitted_at || Time.at(0), expense.auto_number.to_i ] }
             .reverse
      end

      # Counts every tab from the WHOLE list before filtering, so the row of
      # tabs states what is there rather than what the current tab shows.
      def load_claims(lines)
        claims = claims_for_lines(lines)
        @claim_counts = ::Reimbursements::ClaimTabs.counts(claims)
        @claim_tab = ::Reimbursements::ClaimTabs.resolve(params[:status])
        @claims = Kaminari.paginate_array(::Reimbursements::ClaimTabs.filter(claims, @claim_tab))
                          .page(params[:page]).per(CLAIMS_PAGE_SIZE)
      end
    end
  end
end
