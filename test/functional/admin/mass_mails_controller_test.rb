require 'test_helper'

class Admin::MassMailsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test 'should get index' do
    assert MassMail.all.count > 0, "There are no mass mails loaded."

    get :index
    assert_response :success

    assert_not_nil assigns(:mass_mails), 'The mass mails were not assigned by the controller.'
  end

  test 'should get show for draft mail' do
    mass_mail = mass_mails(:draft_mass_mail)

    get :show, params: { id: mass_mail }

    assert_response :success
    assert_equal mass_mail, assigns(:mass_mail), 'The mass mail was not assigned by the controller'
    assert_includes assigns(:title), mass_mail.subject, 'The title does not contain the subject of the mass mail'
  end

  test 'should get show for sent mail' do
    mass_mail = mass_mails(:sent_mass_mail)

    get :show, params: { id: mass_mail }

    assert_response :success
  end

  test 'should get new' do
    get :new
    assert_response :success

    assert assigns(:mass_mail).draft
    assert_no_match 'value="Send"', response.body, 'The send button is visible on the create form'
  end

  test 'should get edit' do
    mass_mail = mass_mails(:draft_mass_mail)

    get :edit, params: { id: mass_mail }

    assert_response :success

    assert_equal mass_mail, assigns(:mass_mail), 'The mass mail was not assigned by the controller'
    assert_match 'value="Send"', response.body, 'The send button is not visibile on the create form'
  end

  test 'cannot edit a mail that is already sent' do
    mass_mail = mass_mails(:sent_mass_mail)

    get :edit, params: { id: mass_mail }

    assert_redirected_to admin_mass_mails_url
  end

  test 'should create mass mail without sending' do
    attributes = FactoryBot.attributes_for(:draft_mass_mail)

    assert_difference('MassMail.count') do
      post :create, params: { mass_mail: attributes }
    end

    assert assigns(:mass_mail).draft, 'The mass mail should not be send, but it is no longer a draft'
    assert_redirected_to admin_mass_mail_path(assigns(:mass_mail)), 'The user was not redirected to the show page. This may indicate that an error occured and it was redirected back to the new page'
  end

  test 'should just save mass mail when creating mass mail with sending' do
    attributes = FactoryBot.attributes_for(:draft_mass_mail)

    assert_no_difference 'ActionMailer::Base.deliveries.count', User.with_role(:member).count do
      assert_difference('MassMail.count') do
        post :create, params: { mass_mail: attributes, send: true }
      end
    end

    assert_nil assigns(:error_message), "An error was caught when catching the mail: #{assigns(:error_message)}"
    assert assigns(:mass_mail).draft, 'The mass email should not be send, but is no longer a draft'
    assert_redirected_to admin_mass_mail_path(assigns(:mass_mail)), 'The user was not redirected to the show page. This may indicate that an error occured and it was redirected back to the new page'
  end

  test 'should not create mass mail that is invalid' do
    attributes = FactoryBot.attributes_for(:draft_mass_mail, subject: '')

    post :create, params: { mass_mail: attributes }

    assert_response :unprocessable_entity
  end

  test 'should update mass mail without sending' do
    mass_mail = mass_mails(:draft_mass_mail)
    attributes = FactoryBot.attributes_for(:draft_mass_mail)

    put :update, params: { id: mass_mail, mass_mail: attributes }

    assert assigns(:mass_mail).draft, 'The mass mail should not be send, but it is no longer a draft'
    assert_redirected_to admin_mass_mail_path(assigns(:mass_mail)), 'The user was not redirected to the show page. This may indicate that an error occured and it was redirected back to the edit page'
  end

  test 'should update mass mail with sending' do
    mass_mail = mass_mails(:draft_mass_mail)
    attributes = FactoryBot.attributes_for(:draft_mass_mail)

    put :update, params: { id: mass_mail, mass_mail: attributes, send: true }

    assert_enqueued_emails User.with_role(:member).count

    assert_nil assigns(:error_message), "An error was caught when catching the mail: #{assigns(:error_message)}"
    assert_not assigns(:mass_mail).draft, 'The mass mail should be send, but it is still a draft'
    assert_redirected_to admin_mass_mail_path(assigns(:mass_mail)), 'The user was not redirected to the show page. This may indicate that an error occured and it was redirected back to the edit page'
  end

  test 'should not update mass mail that is invalid' do
    mass_mail = mass_mails(:draft_mass_mail)
    attributes = FactoryBot.attributes_for(:draft_mass_mail, subject: '')

    put :update, params: { id: mass_mail, mass_mail: attributes }

    assert_response :unprocessable_entity
  end

  test 'should destroy draft admin_mass_mail' do
    mass_mail = mass_mails(:draft_mass_mail)

    assert_difference('MassMail.count', -1) do
      delete :destroy, params: { id: mass_mail }
    end

    assert_redirected_to admin_mass_mails_path, 'The user was not redirected to the index page. This may indicate that an error occured'
  end

  test 'should not destroy sent admin_mass_mail' do
    mass_mail = mass_mails(:sent_mass_mail)

    assert_no_difference('MassMail.count') do
      delete :destroy, params: { id: mass_mail }
    end
  end

  test 'Should not send mail that has already been sent' do
    mass_mail = mass_mails(:sent_mass_mail)

    helper_test_send_mail_with_errors(mass_mail)
  end

  test 'Should not send mail that has a send date in the past' do
    mass_mail = mass_mails(:draft_mass_mail)
    mass_mail.update_attribute :send_date, DateTime.now.advance(days: -1)

    helper_test_send_mail_with_errors(mass_mail)
  end

  test 'Should not send mail when there are no members' do
    mass_mail = mass_mails(:draft_mass_mail)

    members = User.with_role(:member)

    members.each do |member|
      member.remove_role :member
    end

    helper_test_send_mail_with_errors(mass_mail)

    members.each do |member|
      member.add_role :member
    end
  end

  private

  # Testing this function is just a bit annoying because it is not a view.
  def helper_test_send_mail_with_errors(mass_mail)
    @request.format = :json

    assert_no_difference('ActionMailer::Base.deliveries.count') do
      begin
        @controller.send(:send_mail, mass_mail)
      rescue NoMethodError
        # Intentionally, as it cannot find the respond_to things so it will fail.
      end
    end

    # I have not found a way to test that it actually returns :unprocessable entity,
    # This would assert that it has succesfully rendered the edit page with errors, and has not redirected.
    # assert_response :unprocessable_entity, 'The request should have returned an error status code, but it did not'
    assert_not_nil assigns(:error_message), 'The request should have set an error message, but it did not'
  end
end
