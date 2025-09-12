require "test_helper"

class Devise::PasswordsControllerTest < ActionController::TestCase
  test "resetting password for s1234567@sms.ed.ac.uk normalizes to @ed.ac.uk" do
    @request.env["devise.mapping"] = Devise.mappings[:user]

    user = FactoryBot.create(:user, email: "s1234567@sms.ed.ac.uk")

    assert user.email.ends_with?("@ed.ac.uk"), "The email domain was not normalized to @ed.ac.uk"

    # Test if signing in with the unnormalized email works as well.
    post :create, params: { user: { "email" => "s1234567@sms.ed.ac.uk" } }

    assert_redirected_to "/users/sign_in", "If this does not redirect, it likely loaded the same page again with some error. Try looking at the response.body for more information."
  end

  test "resetting password for c.monster@sms.ed.ac.uk normalizes to @ed.ac.uk" do
    @request.env["devise.mapping"] = Devise.mappings[:user]

    user = FactoryBot.create(:user, email: "c.monster@sms.ed.ac.uk")

    assert user.email.ends_with?("@sms.ed.ac.uk"), "The email domain was not normalized to @ed.ac.uk before creating"

    # Try to find that same user and sign in.
    post :create, params: { user: { "email" => "c.monster@sms.ed.ac.uk" } }

    assert_redirected_to "/users/sign_in", "If this does not redirect, it likely loaded the same page again with some error. Try looking at the response.body for more information."
  end
end
