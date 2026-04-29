require "application_system_test_case"

##
# System test for the Stimulus-driven staffing sign-up button.
# Verifies the AJAX flow (no page navigation, success toast, button replaced
# by user name) introduced when porting app/assets/javascripts/admin/staffings.js
# to app/javascript/controllers/staffing_signup_controller.js.
##
class StaffingSignupTest < ApplicationSystemTestCase
  setup do
    # Admin role has every backend permission (including :show on
    # Admin::Staffing and :sign_up_for Admin::StaffingJob), and we need a
    # phone number on file so check_if_current_user_can_sign_up returns true.
    @user = FactoryBot.create(:admin, phone_number: "1234567890")
    login_as @user

    @staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1)
    @job = @staffing.staffing_jobs.first
  end

  test "sign-up form submits via AJAX and replaces button with user name" do
    visit admin_staffing_path(@staffing)

    # The sign-up button is rendered for unstaffed jobs.
    assert_selector "button.staffing-sign-up", count: 1

    find("button.staffing-sign-up").click

    # The app uses SweetAlert in place of the native confirm dialog. Confirm
    # by clicking the "Yes" button inside the modal.
    assert_selector ".swal2-popup", wait: 5
    click_button "Yes"

    # After AJAX completes, the button (and its parent form) should be
    # replaced with a span containing the user's name.
    assert_no_selector "button.staffing-sign-up", wait: 5
    assert_text "#{@user.first_name} #{@user.last_name}"

    # The DB row must be updated server-side.
    assert_equal @user.id, @job.reload.user_id
  end
end
