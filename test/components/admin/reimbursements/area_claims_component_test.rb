require "test_helper"

module Admin
  module Reimbursements
    class AreaClaimsComponentTest < ViewComponent::TestCase
      STATUS = ::Reimbursements::Status

      def claim(number, status)
        expense = ::Reimbursements::Expense.new(status: status, amount: BigDecimal("10"),
                                                description: "Claim #{number}", auto_number: number,
                                                submitted_at: Time.zone.now)
        expense.define_singleton_method(:record_id) { number.to_s }
        expense
      end

      def render_claims(*claims)
        counts = ::Reimbursements::ClaimTabs.counts(claims)
        render_inline(AreaClaimsComponent.new(
                        claims: Kaminari.paginate_array(claims).page(1), counts: counts, tab: "all",
                        finance: false, area: ::Reimbursements::Area.new(id: 7, name: "Cogito")
                      ))
      end

      # A producer reads "Sent to EUSA" on their own claim, so their show's page must say the same.
      test "statuses and tabs use the words a claimant sees on their own claim" do
        render_claims(claim(1, STATUS::SUBMITTED), claim(2, STATUS::PENDING))

        assert_selector "nav a", text: /Sent to EUSA\s+\(1\)/
        assert_selector "nav a", text: /Waiting for review\s+\(1\)/
        assert_selector "tbody td", text: "Sent to EUSA"
        assert_no_text "With EUSA"
        assert_no_text "Waiting for approval"
      end

      test "a status badge carries the portal's own colour for that status" do
        render_claims(claim(1, STATUS::APPROVED))

        assert_selector "tbody span.text-info", text: "Approved"
      end

      # Owners and finance read this page about other people's claims.
      test "the status tooltips never speak to the reader as the claimant" do
        render_claims(claim(1, STATUS::PAID), claim(2, STATUS::REJECTED))

        assert_selector "tbody span[title='EUSA has paid it.']"
        assert_selector "tbody span[title='Not approved, so it will not be paid.']"
        assert_no_selector "tbody span[title*='your']"
      end
    end
  end
end
