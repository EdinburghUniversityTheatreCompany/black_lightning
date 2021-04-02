require 'test_helper'

class Admin::MembershipActivationTokensControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test 'normal users cannot load the new page' do
    sign_out @admin
    sign_in FactoryBot.create(:user)

    get :new

    assert_response 403
  end

  test 'get new' do
    get :new

    assert_response :success
  end

  ##
  # Activation
  ##
  test 'create activation token' do
    assert_difference 'MembershipActivationToken.count' do
      email = 'dennis@donkey.test'

      assert_difference 'ActionMailer::Base.deliveries.count' do
        perform_enqueued_jobs do
          post :create_activation, params: { user: { email: email } }
        end
      end

      assert_equal ["Activation Mail sent to #{email}"], flash[:success]

      assert assigns(:token).present?
      assert_nil assigns(:token).user

      assert_redirected_to new_admin_membership_activation_token_path

      assert_equal [email], ActionMailer::Base.deliveries.last.to
    end
  end

  test 'create activation token for email that belongs to a current user' do
    assert_difference 'MembershipActivationToken.count' do
      user = FactoryBot.create(:user)

      assert_difference 'ActionMailer::Base.deliveries.count' do
        perform_enqueued_jobs do
          post :create_activation, params: { user: { email: user.email } }
        end
      end

      expected_notice = ["The email #{user.email} is already in use by #{user.name(@admin)}. They will be send a reactivation mail.", "Activation Mail sent to #{user.email}"]

      assert_equal expected_notice, flash[:success]

      assert_equal user, assigns(:token).user

      assert_redirected_to new_admin_membership_activation_token_path

      assert_equal [user.email], ActionMailer::Base.deliveries.last.to
    end
  end

  test 'cannot create activation token for email that belongs to a current member' do
    assert_no_difference 'MembershipActivationToken.count' do
      member = FactoryBot.create(:member)

      post :create_activation, params: { user: { email: member.email } }

      expected_notice = ["The email #{member.email} is already in use by #{member.name(@admin)} and they already are a member. They will not be send an activation mail."]
      assert_equal expected_notice, flash[:error]

      assert_response :unprocessable_entity
      assert_not assigns(:token).persisted?

      assert_enqueued_emails 0
    end
  end

  ##
  # Reactivation
  ##
  test 'create reactivation token' do
    assert_difference 'MembershipActivationToken.count' do
      email = 'finbar@bedlamtheatre.co.uk'

      user = FactoryBot.create(:user, email: email)

      assert_difference 'ActionMailer::Base.deliveries.count' do
        perform_enqueued_jobs do
          post :create_reactivation, params: { membership_activation_token: { user_id: user.id } }
        end
      end

      assert_equal ["Reactivation Mail sent to #{user.name(@admin)} at #{user.email}"], flash[:success]
      assert_equal user, assigns(:token).user
      assert_redirected_to new_admin_membership_activation_token_path

      assert_equal [email], ActionMailer::Base.deliveries.last.to
    end
  end

  test 'cannot create reactivation token for user with default email' do
    assert_no_difference 'MembershipActivationToken.count' do
      email = 'unknown_301ofh12kcas0wh@bedlamtheatre.co.uk'

      user = FactoryBot.create(:user, email: email)

      post :create_reactivation, params: { membership_activation_token: { user_id: user.id } }

      assert_includes flash[:error][0], 'This user had their email removed or was exported from the old website.'

      assert_response :unprocessable_entity

      assert_enqueued_emails 0
    end
  end

  test 'cannot create reactivation token for user that is already a member' do
    assert_no_difference 'MembershipActivationToken.count' do
      member = FactoryBot.create(:member)

      post :create_reactivation, params: { membership_activation_token: { user_id: member.id } }

      expected_notice = ["#{member.name(users(:admin))} already is a member and will not be send a reactivation mail."]
      assert_equal expected_notice, flash[:error]

      assert_response :unprocessable_entity

      assert_enqueued_emails 0
    end
  end

  test 'cannot create reactivation token for invalid user id' do
    assert_no_difference 'MembershipActivationToken.count' do
      post :create_reactivation, params: { membership_activation_token: { user_id: -1, user_name_field: 'Finbar the Viking' } }

      expected_notice = ["There is no user with the specified ID. Are you sure the name 'Finbar the Viking' is correct?"]
      assert_equal expected_notice, flash[:error]

      assert_response :unprocessable_entity

      assert_enqueued_emails 0
    end
  end
end
