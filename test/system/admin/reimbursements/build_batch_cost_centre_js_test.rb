require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # Build Batch, clicked for real, in a two-cost-centre portal.
    #
    # A request test cannot cover this: it POSTs straight to #create with
    # whatever parameters it likes, so it passes just as happily when the real
    # form never sends them. The form posts to a bare path with no query string,
    # so the cost centre has to travel in a hidden field — exactly the
    # card.with_footer class of defect CLAUDE.md warns about, where only a
    # browser clicking the actual button can see the difference.
    class BuildBatchCostCentreJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @fringe = ::Reimbursements::CostCentre.default
        @termtime = create_second_reimbursements_cost_centre

        payee = create_reimbursements_person(name: "Alice Producer", email: "alice@example.com",
                                             sort_code: "08-99-99", account_number: "66374958")
        create_reimbursements_expense(
          person: payee, auto_number: 11, status: ::Reimbursements::Status::APPROVED, receipt: false,
          description: "Fringe gaffer tape",
          budget: create_reimbursements_budget(name: "Fringe props", cost_centre: @fringe)
        )
        create_reimbursements_expense(
          person: payee, auto_number: 12, status: ::Reimbursements::Status::APPROVED, receipt: false,
          description: "Termtime gaffer tape",
          budget: create_reimbursements_budget(name: "Termtime props", cost_centre: @termtime)
        )
        login_as users(:member)
      end

      test "the sidebar's Build Batch asks which pot, then submits for the one chosen" do
        # The sidebar link carries no cost centre and never can, so this is the
        # entry point that must not dead-end.
        visit new_admin_reimbursements_batch_path

        assert_text "Pick the pot this batch is for"
        click_on "Bedlam Termtime (BED)"

        # The preview is the money path's ownership read, not the screens'
        # filter: only this centre's claims may be in the spreadsheet.
        assert_text "Termtime gaffer tape"
        assert_no_text "Fringe gaffer tape"

        assert_difference -> { ::Reimbursements::BatchAttempt.count }, +1 do
          click_on "Create draft and process batch"
          within(".swal2-popup") { click_on "Yes" }
          assert_text "Batch is building for Bedlam Termtime", wait: 5
        end

        assert_equal @termtime.id, ::Reimbursements::BatchAttempt.sole.cost_centre_id
      end
    end
  end
end
