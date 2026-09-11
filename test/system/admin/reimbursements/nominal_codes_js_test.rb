require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # The nominal-code list, clicked for real.
    #
    # A request test POSTs straight to the action, so it passes just as
    # happily when the Add form's submit renders OUTSIDE the <form> — which is
    # what a form_with opened inside a CardComponent does, the footer being a
    # component slot. Five defects across Phases 1 and 2a came from exactly
    # that gap, so the add form and the Retire button are clicked here.
    class NominalCodesJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @cost_centre = ::Reimbursements::CostCentre.default
        login_as users(:member)
      end

      # Every row carries the same Save / Retire controls, so a click has to
      # be scoped to the row it belongs to.
      def row_for(nominal_code)
        "#nominal_code_#{nominal_code.record_id}"
      end

      test "adds a nominal code in the browser" do
        visit admin_reimbursements_nominal_codes_path(@cost_centre.key)

        fill_in "Code", with: "432320"
        fill_in "Label", with: "Marketing & publicity"
        click_on "Add nominal code"

        assert_text "432320 added"
        code = ::Reimbursements::NominalCode.find_by(cost_centre: @cost_centre, code: "432320")
        assert_equal "Marketing & publicity", code&.label
        # The new row is on screen, its label editable in place. By field
        # rather than by text: a label lives in an input's value.
        assert_field "label_#{code.record_id}", with: "Marketing & publicity"
      end

      test "corrects a seeded label guess in the browser" do
        nominal_code = create_reimbursements_nominal_code(code: "432320", label: "Marketing",
                                                          cost_centre: @cost_centre)

        visit admin_reimbursements_nominal_codes_path(@cost_centre.key)
        within row_for(nominal_code) do
          fill_in "Label", with: "Marketing & publicity"
          click_on "Save"
        end

        assert_text "432320 saved"
        assert_equal "Marketing & publicity", nominal_code.reload.label
      end

      test "a code a budget carries is retired rather than vanishing" do
        nominal_code = create_reimbursements_nominal_code(code: "432320", label: "Marketing",
                                                          cost_centre: @cost_centre)
        create_reimbursements_budget(name: "Marketing", nominal_code: "432320",
                                     cost_centre: @cost_centre)

        visit admin_reimbursements_nominal_codes_path(@cost_centre.key)
        assert_text "1 budget line booked here"
        within(row_for(nominal_code)) { click_on "Retire" }

        assert_text "432320 retired"
        # Still on screen, and readable: the row is what labels the budget
        # lines already booked against the code.
        assert_text "Retired"
        assert_field "label_#{nominal_code.record_id}", with: "Marketing"
        assert ::Reimbursements::NominalCode.exists?(nominal_code.id)
        assert_not nominal_code.reload.active?
      end

      test "a code nothing carries offers Delete, not Retire" do
        create_reimbursements_nominal_code(code: "999999", cost_centre: @cost_centre)

        visit admin_reimbursements_nominal_codes_path(@cost_centre.key)

        assert_text "No budget lines booked here"
        assert_selector "button", text: "Delete"
        assert_no_selector "button", text: "Retire"
      end
    end
  end
end
