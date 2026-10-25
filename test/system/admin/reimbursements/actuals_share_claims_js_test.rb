require "application_system_test_case"

module Admin
  module Reimbursements
    # Split across claims: only a browser sees the running total and that the submit button is inside
    # the form (the card footer is a component slot; a request test POSTs straight to the action).
    class ActualsShareClaimsJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        budget = create_reimbursements_budget(name: "Props", nominal_code: "432980")
        @claims = [ [ 41, "30.00" ], [ 42, "12.00" ] ].map do |number, amount|
          create_reimbursements_expense(auto_number: number, budget: budget, status: ::Reimbursements::Status::SUBMITTED,
                                        amount: BigDecimal(amount), amount_excl_vat: BigDecimal(amount), receipt: false)
        end
        @payment = create_reimbursements_eusa_actual(debit: BigDecimal("42.00"), narrative: "BACS PAYMENT",
                                                     nominal_code: "432980")
        login_as users(:member)
        visit share_claims_admin_reimbursements_actual_path(@payment.record_id)
      end

      # Clicking the REAL button is what proves it sits inside the <form>.
      test "the running total gates the submit, and the real button settles each claim" do
        assert_button "Save the split", disabled: true

        fill_in "claim_share_#{@claims.first.record_id}", with: "30"
        assert_text "£12.00 left to allocate"
        assert_button "Save the split", disabled: true

        fill_in "claim_share_#{@claims.last.record_id}", with: "12"
        assert_text "The parts add up"
        click_on "Save the split"

        assert_text "Split across #41 and #42, which are now Paid."
        assert_equal [ BigDecimal("12"), BigDecimal("30") ], @payment.reload.claim_shares.map(&:amount).sort
        assert(@claims.all? { |claim| claim.reload.status == ::Reimbursements::Status::PAID })
      end
    end
  end
end
