module Admin
  module Reimbursements
    # The claims table and its tabs. The rows are unpersisted expenses with their
    # DB-computed readers pinned, as the reimbursements unit tests build them.
    class AreaClaimsComponentPreview < ViewComponent::Preview
      def default
        render AreaClaimsComponent.new(claims: claims, counts: counts, tab: "all", finance: false)
      end

      def as_finance
        render AreaClaimsComponent.new(claims: claims, counts: counts, tab: "all", finance: true)
      end

      # The median area in production has no claims at all.
      def no_claims_yet
        render AreaClaimsComponent.new(claims: [], counts: empty_counts, tab: "all", finance: false)
      end

      private

      def claims
        [ claim(246, ::Reimbursements::Status::APPROVED, 97, "Video recordings"),
          claim(100, ::Reimbursements::Status::SUBMITTED, 16.76, "Imps cards shipping fee"),
          claim(39, ::Reimbursements::Status::PAID, 196.91, "Imps Retreat - Food Shop") ]
      end

      def counts
        empty_counts.merge("all" => 3, "approved" => 1, "with_eusa" => 1, "paid" => 1)
      end

      def empty_counts = ::Reimbursements::ClaimTabs::TABS.keys.index_with { 0 }

      def claim(number, status, amount, description)
        expense = ::Reimbursements::Expense.new(
          status: status, amount: BigDecimal(amount.to_s), description: description,
          auto_number: number, submitted_at: Time.zone.now
        )
        expense.define_singleton_method(:record_id) { number.to_s }
        expense
      end
    end
  end
end
