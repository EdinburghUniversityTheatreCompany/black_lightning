module Reimbursements
  ##
  # The status tabs above an area's claims, and the words an owner reads for
  # each one.
  #
  # The portal's own status names are a mix of what the claim IS and where it
  # HAS GOT TO, and two of them mean nothing to a producer: "Submitted" reads
  # as "I submitted it" when it actually means finance has sent it on to EUSA,
  # and "Pending" says nothing about who is holding it. So the tab labels are
  # written from the claimant's side while the stored statuses are untouched.
  #
  # Draft is deliberately absent: a draft is the submitter's unfinished
  # business and belongs on their own claims page, not on a show's ledger.
  module ClaimTabs
    ALL = "all".freeze

    # key => [label, statuses]. Order is the order of the claim's life, so the
    # row of tabs reads left to right as the money moves.
    TABS = {
      ALL => [ "All", nil ],
      "waiting" => [ "Waiting for approval", [ Status::PENDING ] ],
      "approved" => [ "Approved", [ Status::APPROVED ] ],
      "with_eusa" => [ "With EUSA", [ Status::SUBMITTED ] ],
      "paid" => [ "Paid", [ Status::PAID ] ],
      "rejected" => [ "Rejected", [ Status::REJECTED ] ]
    }.freeze

    class << self
      # An unknown or missing ?status= falls back to All rather than showing an
      # empty list, the same rule the Review queue's tabs follow.
      def resolve(requested)
        key = requested.to_s
        TABS.key?(key) ? key : ALL
      end

      def label(key) = TABS.fetch(key, TABS[ALL]).first

      def filter(claims, key)
        statuses = TABS.fetch(key, TABS[ALL]).last
        return claims if statuses.nil?

        claims.select { |claim| statuses.include?(claim.status) }
      end

      # Every tab's count, so the row can be drawn in one pass over the claims
      # rather than one filter per tab.
      def counts(claims)
        TABS.keys.index_with { |key| filter(claims, key).size }
      end

      # The tabs worth drawing: All, plus the ones that have something in them.
      # A row of six tabs where four read "0" is noise on the median area,
      # which has no claims at all.
      def visible(counts)
        TABS.keys.select { |key| key == ALL || counts[key].to_i.positive? }
      end
    end
  end
end
