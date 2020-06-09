require 'test_helper'

class Admin::ShowsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  test 'should get index' do
    FactoryBot.create_list(:show, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:events)
  end

  test 'should get show' do
    @show = FactoryBot.create(:show)

    get :show, params: { id: @show }
    assert_response :success

    assert_no_match 'DM Trained', response.body
  end

  # This mainly tests the show team members partial.
  test 'should get show with a team member that is DM trained' do
    @show = FactoryBot.create(:show)

    @show.users.first.add_role 'DM Trained'

    get :show, params: { id: @show }

    assert_response :success
    assert_match 'DM Trained', response.body
  end

  test 'should get show with staffing debts and maintenance debts' do
    @show = FactoryBot.create(:show)

    FactoryBot.create(:maintenance_debt, show: @show)
    FactoryBot.create(:staffing_debt, show: @show)

    get :show, params: { id: @show }
    assert_response :success
  end

  test 'should get show with debt dates set' do
    @show = FactoryBot.create(:show, is_public: true, staffing_debt_start: Date.today, maintenance_debt_start: Date.today)

    get :show, params: { id: @show }
    assert_response :success 
    assert_match 'Total Amount of Staffing Debts', response.body
  end

  test 'should get new' do
    get :new
    assert_response :success
  end

  test 'should create show' do
    attributes = FactoryBot.attributes_for(:show)

    assert_difference('Show.count') do
      post :create, params: { show: attributes }
    end

    assert_redirected_to admin_show_path(assigns(:show))
  end

  test 'should not create invalid show' do
    attributes = FactoryBot.attributes_for(:show, author: nil)

    assert_no_difference('Show.count') do
      post :create, params: { show: attributes }
    end

    assert_response :unprocessable_entity
  end

  test 'should get edit' do
    @show = FactoryBot.create(:show)

    get :edit, params: { id: @show }
    assert_response :success
  end

  test 'should update show' do
    @show = FactoryBot.create(:show)
    attributes = FactoryBot.attributes_for(:show)

    put :update, params: { id: @show, show: attributes }

    assert_equal attributes[:name], assigns(:show)[:name]
    assert_equal 'The show was successfully updated.', flash[:notice]
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test 'should update show without new debtors' do
    @show = FactoryBot.create(:show)

    users = FactoryBot.create_list(:user, 5) + @show.users
    attributes = FactoryBot.attributes_for(:show, team_members_attributes: team_members_attributes(users))

    # To check if an existing user who is in debt does not count.
    FactoryBot.create(:overdue_staffing_debt, user: @show.users.first)

    assert_no_difference 'ActionMailer::Base.deliveries.count' do
      put :update, params: { id: @show, show: attributes }
    end

    assert_equal 'The show was successfully updated.', flash[:notice]
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test 'should update show with new debtors' do
    @show = FactoryBot.create(:show)
    users = FactoryBot.create_list(:user, 5)
    attributes = FactoryBot.attributes_for(:show, team_members_attributes: team_members_attributes(users))

    FactoryBot.create(:overdue_staffing_debt, user: users.first)

    put :update, params: { id: @show, show: attributes }

    assert_enqueued_emails 1

    assert_equal "The show was successfully updated, but #{users.first.name} is in debt.", flash[:notice]
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test 'should not update invalid show' do
    @show = FactoryBot.create(:show)
    attributes = FactoryBot.attributes_for(:show, price: nil)

    put :update, params: { id: @show, show: attributes }

    assert_response :unprocessable_entity
  end

  test 'should destroy show' do
    @show = FactoryBot.create(:show)

    assert_difference('Show.count', -1) do
      delete :destroy, params: { id: @show }
    end

    assert_redirected_to admin_shows_path
  end

  test 'should create maintenance debts' do
    @show = FactoryBot.create(:show, maintenance_debt_start: Date.today)

    assert_difference 'Admin::MaintenanceDebt.count', @show.team_members.count do
      post :create_maintenance_debts, params: { id: @show.slug }
    end

    assert_redirected_to admin_show_path(@show)
    assert_includes flash[:notice], 'Maintenance obligations created'
  end

  # The authorize is not tested because that's a bit annoying, but make sure
  # that you check that the user can actually create maintenance debts!
  test 'should not create maintenance debts when the maintenance debt start is not set' do
    @show = FactoryBot.create(:show, maintenance_debt_start: nil)

    post :create_maintenance_debts, params: { id: @show.slug }

    assert_redirected_to admin_show_path(@show)
    assert_includes flash[:notice], 'Could not create Maintenance obligations'
  end

  test 'should create staffing debts' do
    @show = FactoryBot.create(:show, staffing_debt_start: Date.today)

    assert_difference 'Admin::StaffingDebt.count', @show.team_members.count * 2 do
      post :create_staffing_debts, params: { id: @show.slug, number_of_slots: 2 }
    end

    assert_redirected_to admin_show_path(@show)
    assert_includes flash[:notice], '2 Staffing obligation slots created'
  end

  # The authorize is not tested because that's a bit annoying, but make sure
  # that you check that the user can actually create staffing debts!
  test 'should not create staffing debts when the requirements are not met' do
    @show = FactoryBot.create(:show, staffing_debt_start: nil)

    post :create_staffing_debts, params: { id: @show.slug }

    assert_redirected_to admin_show_path(@show)
    assert_includes flash[:notice], 'specify the amount'

    post :create_staffing_debts, params: { id: @show.slug, number_of_slots: 2 }

    assert_redirected_to admin_show_path(@show)
    assert_includes flash[:notice], 'Could not create Staffing obligations because the start date has not been set yet.'
  end

  private

  def team_members_attributes(users)
    team_members_attributes = {}

    users.each_with_index do |user, count|
      team_members_attributes[count] = { position: "Viking#{count}", user_name_field: user.name, user_id: user.id, '_destroy'=>'false'}
    end

    return team_members_attributes
  end
end
