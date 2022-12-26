require 'test_helper'

class Admin::MarketingCreatives::ProfilesControllerTest < ActionController::TestCase
  setup do
    @admin = users(:admin)
    sign_in @admin

    @profile = FactoryBot.create(:marketing_creatives_profile)
  end

  test 'should get index' do
    get :index

    assert_response :success
    assert_not_nil assigns(:profiles)
  end

  test 'should get show' do
    # To check there are no render syntax errors.
    FactoryBot.create(:marketing_creatives_category_info, profile: @profile)

    get :show, params: { id: @profile }
    assert_response :success
  end

  test 'random people can see approved status only when not approved' do
    committee = sign_in_as_committee

    @profile.update_attribute(:approved, false)

    get :show, params: { id: @profile }

    assert_includes response.body, '<b>Approved:</b>'
  end

  test 'random people cannot see the approved status when approved' do
    sign_in_as_committee

    @profile.update_attribute(:approved, true)

    get :show, params: { id: @profile }

    assert_not_includes response.body, '<b>Approved:</b>'
  end

  test 'people who can reject can always see the approved state' do
    @profile.update_attribute(:approved, true)

    get :show, params: { id: @profile }
    assert_response :success

    assert_includes response.body, '<b>Approved:</b>'
  end

  test 'people without manage permission cannot see ID and user' do
    sign_in_as_committee

    @profile.update_attribute(:user, users(:user))

    get :show, params: { id: @profile }
    assert_response :success

    assert_not_includes response.body, '<b>ID:</b>'
    assert_not_includes response.body, '<b>User:</b>'
  end

  test 'people with manage permission can see ID and user' do
    @profile.update_attribute(:user, users(:user))

    get :show, params: { id: @profile }

    assert_includes response.body, '<b>ID:</b>'
    assert_includes response.body, '<b>User:</b>'
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should get sign_up' do
    get :sign_up
    assert_response :success

    assert_not assigns(:profile).persisted?
  end

  test 'should not get sign up if the user already has a profile' do
    @profile.update_attribute(:user, @admin)

    get :sign_up

    assert_redirected_to admin_marketing_creatives_profile_path(@profile)

    assert_not_nil flash[:error]
  end

  test 'should create profile without manage' do
    committee = sign_in_as_committee

    # Check that the approved setting is set to false.
    attributes = FactoryBot.attributes_for(:marketing_creatives_profile)
    attributes[:approved] = true

    assert_difference('MarketingCreatives::Profile.count') do
      post :create, params: { marketing_creatives_profile: attributes }
    end

    assert_not assigns(:profile).approved
    assert_equal committee, assigns(:profile).user

    assert_redirected_to admin_marketing_creatives_profile_path(assigns(:profile))
  end

  test 'should not create if the user already has a profile' do
    committee = sign_in_as_committee
  
    @profile.update_attribute(:user, committee)

    attributes = FactoryBot.attributes_for(:marketing_creatives_profile)

    assert_no_difference('MarketingCreatives::Profile.count') do
      post :create, params: { marketing_creatives_profile: attributes }
    end

    assert_redirected_to admin_marketing_creatives_profile_path(@profile)

    assert_not_nil flash[:error]
  end

  test 'should create if the user has a profile but can manage' do
    @profile.update_attribute(:user, @admin)

    attributes = FactoryBot.attributes_for(:marketing_creatives_profile)

    assert_difference('MarketingCreatives::Profile.count') do
      post :create, params: { marketing_creatives_profile: attributes }
    end

    assert_redirected_to admin_marketing_creatives_profile_path(assigns(:profile))

    assert_nil flash[:error]
  end

  test 'should not create invalid profile' do
    attributes = FactoryBot.attributes_for(:marketing_creatives_profile)
    attributes[:name] = nil 

    assert_no_difference('MarketingCreatives::Profile.count') do
      post :create, params: { marketing_creatives_profile: attributes }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    get :edit, params: { id: @profile }
    assert_response :success
  end

  test 'should not show user field if the user cannot manage' do
    committee = sign_in_as_committee

    # This way we don't have to give committee permission to edit in the fixtures.
    committee.marketing_creatives_profile = @profile

    get :edit, params: { id: @profile }
    assert_response :success

    assert_not_includes response.body, 'id="marketing_creatives_profile_user_id"'
  end

  test 'should show user field if the user can manage' do
    get :edit, params: { id: @profile }

    assert_includes response.body, 'id="marketing_creatives_profile_user_id"'
  end

  test 'should update profile' do
    attributes = FactoryBot.attributes_for(:marketing_creatives_profile)

    put :update, params: { id: @profile, marketing_creatives_profile: attributes }

    assert attributes[:name], assigns(:profile).name
    assert_redirected_to admin_marketing_creatives_profile_path(@profile)
  end
  
  test 'should not update invalid profile' do
    attributes = FactoryBot.attributes_for(:marketing_creatives_profile)
    attributes[:about] = nil 

    put :update, params: { id: @profile, marketing_creatives_profile: attributes }

    assert_response :unprocessable_entity
  end

  test 'should destroy profile' do
    @profile.category_infos.clear

    assert_difference('MarketingCreatives::Profile.count', -1) do
      delete :destroy, params: { id: @profile }
    end

    assert_redirected_to admin_marketing_creatives_profiles_path
  end

  test 'should not destroy profile with attached infos' do
    category_info = FactoryBot.create(:marketing_creatives_category_info, profile: @profile)

    assert_no_difference('MarketingCreatives::Profile.count') do
      delete :destroy, params: { id: @profile }
    end

    assert_redirected_to admin_marketing_creatives_profile_path(@profile)
  end

  test 'should approve' do
    @profile.update_attribute(:approved, false)

    put :approve, params: { id: @profile }

    assert assigns(:profile).approved

    assert_redirected_to admin_marketing_creatives_profile_path(@profile)
  end

  test 'should reject' do
    @profile.update_attribute(:approved, true)

    put :reject, params: { id: @profile }

    assert_not assigns(:profile).approved

    assert_redirected_to admin_marketing_creatives_profile_path(@profile)
  end

  private 

  def sign_in_as_committee
    sign_out @admin
    committee = users(:committee)
    sign_in committee

    return committee
  end
end
