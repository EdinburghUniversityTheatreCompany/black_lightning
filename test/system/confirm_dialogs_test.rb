require "application_system_test_case"

# The button_to forms that ask before they act. Those whose redirect lands on another layout (the
# two that sign the user out, and get_link's buttons on the public site) submit natively
# (confirm_controller), so their flash survives; under data-turbo-confirm it was lost.
class ConfirmDialogsTest < ApplicationSystemTestCase
  test "Log Out asks first; Cancel keeps the session and Yes ends it" do
    login_as users(:admin)
    visit admin_path

    within("aside") { click_button "Log Out" }
    assert_selector ".swal2-popup", text: "Are you sure you want to log out?"
    click_button "Cancel"
    assert_no_selector ".swal2-popup"

    within("aside") { click_button "Log Out" }
    within(".swal2-popup") { click_button "Yes" }

    assert_text "Logged out successfully."
    visit admin_path
    assert_current_path new_user_session_path
  end

  test "destroying a show from its public page asks first and keeps the flash" do
    show = FactoryBot.create(:show, name: "Finbar's Farewell")
    login_as users(:admin)

    visit show_path(show)
    click_button "Destroy"
    assert_selector ".swal2-popup", text: "Are you sure you want to delete the Show \"Finbar's Farewell\"?"
    within(".swal2-popup") { click_button "Yes" }

    assert_text "has been successfully destroyed."
    assert_not Show.exists?(show.id)
  end

  test "removing a user from a role asks first" do
    login_as users(:admin)
    role = roles(:committee)
    user = FactoryBot.create(:user, first_name: "Finbar", last_name: "the Viking")
    user.add_role(role.name)

    visit admin_role_path(role)
    within("tr", text: "Finbar the Viking") { click_button "Remove" }
    assert_selector ".swal2-popup", text: "Remove Finbar the Viking from this role?"
    within(".swal2-popup") { click_button "Yes" }

    assert_text "Finbar the Viking has been removed from the role of Committee"
    assert_not user.reload.has_role?(role.name)
  end

  test "regenerating the calendar link asks first" do
    user = users(:admin)
    user.regenerate_calendar_token
    old_token = user.reload.calendar_token
    login_as user

    visit admin_staffings_path
    click_button "Regenerate link"
    assert_selector ".swal2-popup", text: "This will invalidate your current link."
    within(".swal2-popup") { click_button "Yes" }

    assert_text "Your calendar link has been regenerated."
    assert_not_equal old_token, user.reload.calendar_token
  end

  test "cancelling an account asks first" do
    user = FactoryBot.create(:user)
    login_as user

    visit edit_user_registration_path
    click_button "Cancel my account"
    assert_selector ".swal2-popup", text: "Are you sure you want to cancel your account? This cannot be undone."
    within(".swal2-popup") { click_button "Yes" }

    assert_text "Your account has been successfully cancelled."
    assert_not User.exists?(user.id)
  end
end
