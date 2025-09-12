require "test_helper"

class StaticControllerTest < ActionController::TestCase
  include ActionDispatch::Routing::UrlFor
  test "should get home" do
    FactoryBot.create_list(:show, 10)

    get :home
    assert_response :success
  end

  test "should get contact" do
    get :show, params: { page: "contact" }
    assert_response :success
  end

  test "should get 404 when navigating to nonexistent page" do
    get :show, params: { page: "pineapples_and_the_hexagon_a_memoir" }
    assert_response 404
  end

  test "should get privacy policy" do
    get :show, params: { page: "privacy_policy" }
    assert_response :success
  end

  test "should submit contact form" do
    params = {
      email: "sender@bedlamtheatre.co.uk",
      name: "Finbar the Viking",
      recipient: "recipient@bedlamtheatre.co.uk",
      subject: "My Wondrous Adventures",
      message: "Make sure to learn more"
    }

    assert_difference "ActionMailer::Base.deliveries.count" do
      perform_enqueued_jobs do
        post :contact_form_send, params: { contact: params }
      end

      mail = ActionMailer::Base.deliveries.last

      assert_equal [ params[:email], params[:recipient] ], mail.to
      assert_equal params[:subject], mail.subject

      assert_includes mail.body.to_s, params[:message]
      assert_includes mail.body.to_s, params[:name]
    end

    assert_redirected_to static_path("contact")
  end
end
