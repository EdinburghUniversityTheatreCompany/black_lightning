module Reimbursements
  ##
  # The status tabs above an area's claims, labelled from the claimant's side:
  # "Submitted" reads as "I submitted it" and "Pending" says nothing about who
  # holds the claim. Draft is absent: it belongs on the submitter's own page.
  module ClaimTabs
    ALL = "all".freeze

    # key => [label, statuses], in the order the money moves.
    TABS = {
      ALL => [ "All", nil ],
      "waiting" => [ "Waiting for approval", [ Status::PENDING ] ],
      "approved" => [ "Approved", [ Status::APPROVED ] ],
      "with_eusa" => [ "With EUSA", [ Status::SUBMITTED ] ],
      "paid" => [ "Paid", [ Status::PAID ] ],
      "rejected" => [ "Rejected", [ Status::REJECTED ] ]
    }.freeze

    class << self
      # An unknown or missing ?status= falls back to All, not an empty list.
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

      def counts(claims)
        TABS.keys.index_with { |key| filter(claims, key).size }
      end

      # All, plus the tabs with something in them: the median area has no claims.
      def visible(counts)
        TABS.keys.select { |key| key == ALL || counts[key].to_i.positive? }
      end
    end
  end
end
