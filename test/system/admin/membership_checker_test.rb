require "application_system_test_case"

class Admin::MembershipCheckerTest < ApplicationSystemTestCase
  # The result names the person, and people edit their own names.
  test "the result shows markup in a name as text" do
    FactoryBot.create(:editable_block, url: "admin/resources/membership_checker")
    FactoryBot.create(:user, first_name: "Markup", last_name: "<b>x</b>")
    login_as users(:admin)

    visit admin_resources_membership_checker_path
    fill_in "membershipSearch", with: "Markup"
    click_button "Submit"

    assert_selector ".swal2-popup", text: "Markup <b>x</b> is not a current member"
    assert_no_selector ".swal2-popup b"
  end
end
