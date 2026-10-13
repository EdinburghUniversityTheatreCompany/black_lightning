module Reimbursements
  ##
  # The status tabs above an area's claims. Each is named with its status's producer word
  # (ReimbursementsHelper::PRODUCER_STATUS), so a claimant reads the same word here as on
  # their own claim. Draft is absent: it belongs on the submitter's own page.
  module ClaimTabs
    ALL = "all".freeze

    # key => status, in the order the money moves.
    TABS = {
      ALL => nil,
      "waiting" => Status::PENDING,
      "approved" => Status::APPROVED,
      "with_eusa" => Status::SUBMITTED,
      "paid" => Status::PAID,
      "rejected" => Status::REJECTED
    }.freeze

    class << self
      # An unknown or missing ?status= falls back to All, not an empty list.
      def resolve(requested)
        key = requested.to_s
        TABS.key?(key) ? key : ALL
      end

      def label(key)
        status = TABS[key]
        status ? ReimbursementsHelper::PRODUCER_STATUS.fetch(status).first : "All"
      end

      def filter(claims, key)
        status = TABS[key]
        return claims if status.nil?

        claims.select { |claim| claim.status == status }
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
