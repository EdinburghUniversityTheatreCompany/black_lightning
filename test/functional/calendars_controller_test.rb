require "test_helper"

class CalendarsControllerTest < ActionController::TestCase
  setup do
    @user = FactoryBot.create(:user)
    @user.regenerate_calendar_token
    @user.reload

    future_staffing = FactoryBot.create(:staffing,
      start_time: 2.days.from_now,
      end_time:   2.days.from_now + 2.hours
    )
    @job = FactoryBot.create(:staffing_job, staffable: future_staffing, user: @user)
  end

  test "returns a text/calendar feed with a UID for each upcoming job for a valid token" do
    get :staffing, params: { token: @user.calendar_token }

    assert_response :success
    assert_equal "text/calendar", response.media_type
    assert_includes response.body, "staffing-job-#{@job.id}@bedlamtheatre.co.uk"
  end

  test "returns 404 for unknown token" do
    get :staffing, params: { token: "notarealtoken" }

    assert_response :not_found
  end

  test "omits past jobs" do
    past_staffing = FactoryBot.create(:staffing,
      start_time: 3.days.ago,
      end_time:   3.days.ago + 2.hours
    )
    past_job = FactoryBot.create(:staffing_job, staffable: past_staffing, user: @user)

    get :staffing, params: { token: @user.calendar_token }

    assert_not_includes response.body, "staffing-job-#{past_job.id}@bedlamtheatre.co.uk"
  end

  test "regenerate_token requires authentication" do
    post :regenerate_token
    assert_redirected_to new_user_session_path
  end

  test "regenerate_token changes token and redirects" do
    sign_in @user
    old_token = @user.calendar_token

    post :regenerate_token

    @user.reload
    assert_not_equal old_token, @user.calendar_token
    assert_redirected_to admin_staffings_path
  end
end
