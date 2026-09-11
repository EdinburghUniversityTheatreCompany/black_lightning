require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # The nominal-code list on the cost centre's own edit page, clicked for
    # real.
    #
    # A request test POSTs straight to the action, so it passes just as
    # happily when the Add button submits nothing — which is what it does if
    # the section is nested inside the cost centre's `simple_form_for` (a form
    # within a form is invalid HTML) or if a submit lands in a CardComponent's
    # footer slot. Five defects across Phases 1 and 2a came from that class of
    # gap, so the real controls are clicked here.
    class NominalCodesJsTest < ApplicationSystemTestCase
      include ReimbursementsTestHelpers

      setup do
        grant_finance_permission(users(:member))
        @cost_centre = ::Reimbursements::CostCentre.default
        login_as users(:member)
      end

      def settings_page
        edit_admin_reimbursements_setting_path(@cost_centre.key)
      end

      # Every row carries the same Save / Retire controls, so a click has to
      # be scoped to the row it belongs to.
      def row_for(nominal_code)
        "#nominal_code_#{nominal_code.record_id}"
      end

      test "adds a nominal code from the cost centre's edit page" do
        visit settings_page

        within "#nominal_codes" do
          fill_in "Code", with: "432320"
          fill_in "Label", with: "Marketing & publicity"
          click_on "Add nominal code"
        end

        assert_text "432320 added"
        code = ::Reimbursements::NominalCode.find_by(cost_centre: @cost_centre, code: "432320")
        assert_equal "Marketing & publicity", code&.label
        # The new row is on screen, its label editable in place. By field
        # rather than by text: a label lives in an input's value.
        assert_field "label_#{code.record_id}", with: "Marketing & publicity"
      end

      # The section answers with a turbo stream replacing itself alone, so the
      # cost centre's own form is never re-rendered under the operator.
      test "adding a code leaves a half-typed cost centre field alone" do
        visit settings_page

        fill_in "EUSA contact name", with: "Half typed"
        within "#nominal_codes" do
          fill_in "Code", with: "432320"
          fill_in "Label", with: "Marketing"
          click_on "Add nominal code"
        end

        assert_text "432320 added"
        assert_field "EUSA contact name", with: "Half typed"
        assert_nil @cost_centre.reload.eusa_contact_name
      end

      test "corrects a seeded label guess in the browser" do
        nominal_code = create_reimbursements_nominal_code(code: "432320", label: "Marketing",
                                                          cost_centre: @cost_centre)

        visit settings_page
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

        visit settings_page
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

        visit settings_page

        assert_text "Nothing booked here"
        within "#nominal_codes" do
          assert_selector "button", text: "Delete"
          assert_no_selector "button", text: "Retire"
        end
      end
    end
  end
end
