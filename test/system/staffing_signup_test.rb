require "application_system_test_case"

# The sign-up button signs up without navigating and is replaced by the user's name.
class StaffingSignupTest < ApplicationSystemTestCase
  setup do
    # Admin role plus a phone number, so check_if_current_user_can_sign_up returns true.
    @user = FactoryBot.create(:admin, phone_number: "1234567890")
    login_as @user

    @staffing = FactoryBot.create(:staffing, unstaffed_job_count: 1)
    @job = @staffing.staffing_jobs.first
  end

  test "sign-up form submits via AJAX and replaces button with user name" do
    visit admin_staffing_path(@staffing)

    assert_selector "button.staffing-sign-up", count: 1

    find("button.staffing-sign-up").click

    # SweetAlert replaces the native confirm dialog.
    assert_selector ".swal2-popup", wait: 5
    click_button "Yes"

    assert_no_selector "button.staffing-sign-up", wait: 5
    assert_text "#{@user.first_name} #{@user.last_name}"
    # The sign-up toast opts in to HTML, so its calendar link must render as a link.
    assert_selector ".swal2-container a[href^='http://www.google.com/calendar']", text: "Add to Google Calendar"

    assert_equal @user.id, @job.reload.user_id
  end
end
