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

      # The real values ride along so the toggle needs no round trip.
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

      # Nothing to reveal: a bare dash, no toggle.
      test "renders a plain dash and no toggle when there are no details on file" do
        render_details(sort_code: "", account_number: "")

        assert_text "-"
        assert_no_selector "button"
      end

      test "masks each half independently when only one is on file" do
        render_details(account_number: "")

        assert_text "****9999 / -"
      end

      test "an IBAN replaces the pair, masked to its last four digits and revealed grouped in fours" do
        render_inline(BankDetailsComponent.new(iban: "DE89370400440532013000", payee: "Studio Bühne"))

        value = page.find("[data-bank-details-target='value']", visible: :all)
        assert_equal "****3000", value.text
        assert_equal "****3000", value["data-masked"]
        assert_equal "DE89 3704 0044 0532 0130 00", value["data-revealed"]
        assert_selector "button[aria-label='Reveal bank details for Studio Bühne']"
      end

      test "a blank IBAN renders a plain dash and no toggle" do
        render_inline(BankDetailsComponent.new(iban: ""))

        assert_text "-"
        assert_no_text "- / -"
        assert_no_selector "button"
      end
    end
  end
end
