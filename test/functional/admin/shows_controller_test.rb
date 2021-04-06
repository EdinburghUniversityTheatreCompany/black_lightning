require 'test_helper'

class Admin::ShowsControllerTest < ActionController::TestCase
  include AcademicYearHelper

  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test 'should get index' do
    FactoryBot.create_list(:show, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:events)
  end

  test 'should get random show' do
    FactoryBot.create_list(:show, 10)

    get :index, params: { commit: 'Random' }

    # Due to the randomness, can't get it to be more specific than
    # checking for a redirect.
    assert_response :redirect
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
    @show = FactoryBot.create(:show, is_public: true, end_date: start_of_year, staffing_debt_start: Date.today, maintenance_debt_start: Date.today)

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
    assert_equal ["The Show '#{attributes[:name]}' was successfully updated."], flash[:success]
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

    assert_equal ["The Show '#{attributes[:name]}' was successfully updated."], flash[:success]

    assert_redirected_to admin_show_path(assigns(:show))
  end

  test 'should update show with new debtors' do
    @show = FactoryBot.create(:show)
    users = FactoryBot.create_list(:user, 5)
    attributes = FactoryBot.attributes_for(:show, team_members_attributes: team_members_attributes(users), start_date: start_of_year.advance(days: 1))

    FactoryBot.create(:overdue_staffing_debt, user: users.first)

    put :update, params: { id: @show, show: attributes }

    assert_enqueued_emails 1

    assert_equal ["The show was successfully updated, but #{users.first.name} is in debt."], flash[:notice]
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test 'should not update invalid show' do
    @show = FactoryBot.create(:show)
    attributes = FactoryBot.attributes_for(:show, price: nil)

    put :update, params: { id: @show, show: attributes }

    assert_response :unprocessable_entity
  end


  test 'should destroy show' do
    @show = FactoryBot.create(:show, team_member_count: 0, picture_count: 0, review_count: 0)
  
    assert_difference('Show.count', -1) do
      delete :destroy, params: { id: @show }

      assert_nil flash[:errors]
    end

    assert_redirected_to admin_shows_path
  end

  test 'should not destroy show with team members' do
    @show = FactoryBot.create(:show, team_member_count: 1)

    assert_no_difference 'Show.count' do
      delete :destroy, params: { id: @show }
    end
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

  test 'convert to season' do
    show = FactoryBot.create(:show, review_count: 0)

    assert_difference('Show.count', -1) do
      assert_difference('Season.count', 1) do
        post :convert_to_season, params: { id: show }
      end
    end

    season = Season.find(show.id)

    assert_equal season.name, show.name
    assert_equal season.picture_ids, show.picture_ids
    assert_equal season.team_member_ids, show.team_member_ids
  end

  test 'convert to workshop' do
    show = FactoryBot.create(:show, review_count: 0)

    assert_difference('Show.count', -1) do
      assert_difference('Workshop.count', 1) do
        post :convert_to_workshop, params: { id: show }
      end
    end
    
    workshop = Workshop.find(show.id)

    assert_equal workshop.name, show.name
    assert_equal workshop.picture_ids, show.picture_ids
    assert_equal workshop.team_member_ids, show.team_member_ids
  end

  # Assuming it also will not convert to a Workshop in this case.
  test 'cannot convert to season when there is stuff attached' do
    show = FactoryBot.create(:show, review_count: 1)

    assert_no_difference('Show.count') do
      assert_no_difference('Season.count') do
        post :convert_to_season, params: { id: show }
      end
    end

    assert_equal ["There are still attached reviews or feedbacks left. You cannot convert a show with one of these attached to prevent data loss."], flash[:error]
  end

  # Assuming it also will not convert to a Season in this case.
  test 'converting to workshop with identical slug gives error' do
    show = FactoryBot.create(:show, review_count: 0)
    workshop = FactoryBot.create(:workshop, slug: show.slug)

    assert_no_difference('Show.count') do
      assert_no_difference('Workshop.count') do
        post :convert_to_workshop, params: { id: show }
      end
    end

    assert_equal ["Could not create Workshop '#{show.name}' from the Show '#{show.name}'. There already exists a Workshop with the slug '#{show.slug}'"], flash[:error]
  end

  test 'cannot convert without permission' do
    sign_out @admin
    sign_in FactoryBot.create(:committee)

    show = FactoryBot.create(:show, review_count: 0)

    post :convert_to_workshop, params: { id: show }

    assert_response 403
  end

  test 'upload pictures using dropzone' do
    attributes = FactoryBot.attributes_for(:show)

    file_data = [
      fixture_file_upload(Rails.root.join('test', 'test.png'), 'image/png')
    ]

    attributes[:dropzone_pictures] = file_data

    assert_difference('Show.count') do
      assert_difference('Picture.count', file_data.size) do
        post :create, params: { show: attributes }
      end
    end

    assert assigns(:show).pictures.count, file_data.size

    assert_redirected_to admin_show_path(assigns(:show))
  end

  test 'raises error when dropzoning something random' do
    assert_raises ArgumentError do
      @show = FactoryBot.create(:show)
      attributes = FactoryBot.attributes_for(:show)

      attributes[:dropzone_finbar] = ['the', 'content', 'should', 'not', 'matter']

      put :update, params: { id: @show, show: attributes }
    end
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
