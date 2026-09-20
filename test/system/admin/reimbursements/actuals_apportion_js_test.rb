require "application_system_test_case"

module Admin
  module Reimbursements
    # Browser tests for the split-an-EUSA-credit screen. Two things only a real
    # browser sees: the running total that tells the operator whether the parts
    # add up, and that the submit button is INSIDE the form — the card footer is
    # a component slot, so a form opened inside the card renders its submit
    # outside the <form> and the button silently does nothing. A request-level
    # test POSTs straight to the action and cannot catch that.
    class ActualsApportionJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @payout = create_reimbursements_eusa_actual(credit: BigDecimal("4000"),
                                                    narrative: "STRIPE PAYOUT AUG")
        create_reimbursements_budget(name: "Show A", budget_type: "Income", nominal_code: "4100")
        create_reimbursements_budget(name: "Show B", budget_type: "Income", nominal_code: "4100")
        login_as users(:member)
        visit apportion_admin_reimbursements_actual_path(@payout.record_id)
      end

      # Tom Select hides the original <select>, so Capybara's own #select can't
      # touch it. Drive the widget the way an operator does.
      def tom_select(option_text, select_id:)
        wrapper = find("##{select_id}", visible: :any).find(:xpath, "..")
        wrapper.find(".ts-control").click
        wrapper.find(".ts-dropdown-content .option", text: option_text, match: :first).click
      end

      def type_share(row, budget_name, amount)
        tom_select(budget_name, select_id: "share_#{row}_budget_id")
        fill_in "share_#{row}_amount", with: amount
      end

      test "the running total updates as amounts are typed and gates the submit" do
        assert_button "Save the split", disabled: true

        type_share(0, "Show A", "2500")

        assert_text "£1,500.00 left to allocate"
        assert_button "Save the split", disabled: true

        type_share(1, "Show B", "1500")

        assert_text "The parts add up"
        assert_button "Save the split", disabled: false
      end

      test "over-allocating disables the submit again" do
        type_share(0, "Show A", "2500")
        type_share(1, "Show B", "2500")

        assert_text "£1,000.00 over"
        assert_button "Save the split", disabled: true
      end

      # Clicking the REAL button is what proves it sits inside the <form>.
      test "clicking the real submit writes the shares" do
        type_share(0, "Show A", "2500")
        type_share(1, "Show B", "1500")
        click_on "Save the split"

        assert_text "Split across 2 budgets"
        assert_equal [ BigDecimal("1500"), BigDecimal("2500") ],
                     @payout.reload.allocations.map(&:amount).sort
      end
    end
  end
end
