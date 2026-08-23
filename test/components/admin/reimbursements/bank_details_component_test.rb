require "test_helper"

module Admin
  module Reimbursements
    class BankDetailsComponentTest < ViewComponent::TestCase
      def render_details(**attrs)
        render_inline(BankDetailsComponent.new(
                        **{ sort_code: "08-99-99", account_number: "66374958" }.merge(attrs)
                      ))
      end

      test "shows the masked pair, not the account number" do
        render_details

        assert_text "****9999 / ****4958"
        assert_no_text "66374958"
      end

      # The real values ride along in data attributes: the operator is entitled
      # to them, and the toggle must not need a round trip. What this component
      # buys is that reading one is a deliberate act.
      test "carries the full pair for the toggle to swap in" do
        render_details

        value = page.find("[data-bank-details-target='value']", visible: :all)
        assert_equal "****9999 / ****4958", value["data-masked"]
        assert_equal "08-99-99 / 66374958", value["data-revealed"]
      end

      test "the toggle names the payee so a table of claims is navigable by screen reader" do
        render_details(payee: "Pat Producer")

        assert_selector "button[aria-label='Reveal bank details for Pat Producer'][aria-pressed='false']"
      end

      test "the toggle still has a name when there is no payee to give it" do
        render_details

        assert_selector "button[aria-label='Reveal bank details']"
      end

      # Nothing to hide and nothing to reveal: a bare dash, no toggle inviting a
      # click that would do nothing.
      test "renders a plain dash and no toggle when there are no details on file" do
        render_details(sort_code: "", account_number: "")

        assert_text "-"
        assert_no_selector "button"
      end

      test "masks each half independently when only one is on file" do
        render_details(account_number: "")

        assert_text "****9999 / -"
      end
    end
  end
end
