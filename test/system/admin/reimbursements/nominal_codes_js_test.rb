require "application_system_test_case"

module Admin
  module Reimbursements
    ##
    # The nominal-code controls clicked for real. A request test passes even
    # when the Add button submits nothing: the section nested in the centre's
    # form, or a submit in a card's footer slot.
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

      # Every row has the same controls, so a click is scoped to its row.
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
        # By field, not text: the label is an input's value.
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
          click_on "Save label"
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
        # Still listed: it labels the lines already booked against it.
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
