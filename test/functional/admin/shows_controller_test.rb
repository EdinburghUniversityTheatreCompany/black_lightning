require "test_helper"

class Admin::ShowsControllerTest < ActionController::TestCase
  include AcademicYearHelper

  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test "should get index" do
    FactoryBot.create_list(:show, 3)

    get :index
    assert_response :success
    assert_not_nil assigns(:events)
  end

  test "should get random show" do
    FactoryBot.create_list(:show, 3)

    get :index, params: { commit: "Random" }

    # Due to the randomness, can't get it to be more specific than
    # checking for a redirect.
    assert_response :redirect
    assert_not_nil assigns(:events)
  end

  test "should get show" do
    @show = FactoryBot.create(:show)

    get :show, params: { id: @show }
    assert_response :success

    assert_no_match "DM Trained", response.body
  end

  # This mainly tests the show team members partial.
  test "should get show with a team member that is DM trained" do
    @show = FactoryBot.create(:show, team_member_count: 1)

    @show.users.first.add_role "DM Trained"

    get :show, params: { id: @show }

    assert_response :success
    assert_match "DM Trained", response.body
  end

  test "should get show with staffing debts and maintenance debts" do
    @show = FactoryBot.create(:show)

    FactoryBot.create(:maintenance_debt, show: @show)
    FactoryBot.create(:staffing_debt, show: @show)

    get :show, params: { id: @show }
    assert_response :success
  end

  test "should get show with debt settings section for current academic year show" do
    @show = FactoryBot.create(:show, is_public: true, end_date: start_of_year.advance(days: 1), start_date: start_of_year)

    get :show, params: { id: @show }
    assert_response :success
    assert_match "Debt Settings", response.body
  end

  test "should not show debt settings for old show" do
    @show = FactoryBot.create(:show, is_public: true, end_date: start_of_year.advance(years: -2), start_date: start_of_year.advance(years: -2))

    get :show, params: { id: @show }
    assert_response :success
    assert_no_match "Debt Settings", response.body
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create show" do
    attributes = FactoryBot.attributes_for(:show)

    assert_difference("Show.count") do
      post :create, params: { show: attributes }
    end

    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should not create invalid show" do
    attributes = FactoryBot.attributes_for(:show, author: nil)

    assert_no_difference("Show.count") do
      post :create, params: { show: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit" do
    @show = FactoryBot.create(:show)

    get :edit, params: { id: @show }
    assert_response :success
  end

  test "should update show" do
    @show = FactoryBot.create(:show)
    attributes = FactoryBot.attributes_for(:show)

    put :update, params: { id: @show, show: attributes }

    assert_equal attributes[:name], assigns(:show)[:name]
    assert_equal [ "The Show \"#{attributes[:name]}\" was successfully updated." ], flash[:success]
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should update show without new debtors" do
    @show = FactoryBot.create(:show, team_member_count: 1)

    users = FactoryBot.create_list(:user, 3)
    attributes = FactoryBot.attributes_for(:show, team_members_attributes: team_members_attributes(users))

    # To check if an existing user who is in debt does not count.
    FactoryBot.create(:overdue_staffing_debt, user: @show.users.first)

    assert_no_difference "ActionMailer::Base.deliveries.count" do
      put :update, params: { id: @show, show: attributes }
    end

    assert_empty assigns(:show).errors.full_messages, "There are errors on the show"
    assert_equal [ "The Show \"#{attributes[:name]}\" was successfully updated." ], flash[:success]

    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should update show with new debtors" do
    @show = FactoryBot.create(:show)
    users = FactoryBot.create_list(:user, 5)
    attributes = FactoryBot.attributes_for(:show, team_members_attributes: team_members_attributes(users), start_date: start_of_year.advance(days: 1))

    FactoryBot.create(:overdue_staffing_debt, user: users.first)

    put :update, params: { id: @show, show: attributes }

    assert_enqueued_emails 1

    assert_equal "The show was successfully updated, but #{users.first.name} is in debt.", flash[:success].first
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "should not update invalid show" do
    @show = FactoryBot.create(:show)
    attributes = FactoryBot.attributes_for(:show, price: nil)

    put :update, params: { id: @show, show: attributes }

    assert_response :unprocessable_entity
  end

  test "should preserve author field when update fails" do
    @show = FactoryBot.create(:show, author: "Original Author")
    new_author = "Brand New Custom Author"

    # Create attributes that will fail validation (missing venue which is required)
    attributes = FactoryBot.attributes_for(:show, author: new_author)
    attributes[:venue_id] = nil  # This will cause validation to fail

    put :update, params: { id: @show, show: attributes }

    assert_response :unprocessable_entity

    # The author field should be preserved in the form when re-rendered
    # Check that the assigned show object has the new author value
    assert_equal new_author, assigns(:show).author, "Author field should preserve the submitted value when validation fails"
  end

  test "should preserve author field with whitespace when update fails" do
    @show = FactoryBot.create(:show, author: "Original Author")
    new_author_with_whitespace = "  Custom Author With Spaces  "

    # Create attributes that will fail validation (missing venue which is required)
    attributes = FactoryBot.attributes_for(:show, author: new_author_with_whitespace)
    attributes[:venue_id] = nil  # This will cause validation to fail

    put :update, params: { id: @show, show: attributes }

    assert_response :unprocessable_entity

    # The author field should be normalized (trimmed) but preserved
    expected_author = "Custom Author With Spaces"  # Normalized version
    assert_equal expected_author, assigns(:show).author, "Author field should preserve the normalized value when validation fails"
  end

  test "should preserve empty author field when update fails" do
    @show = FactoryBot.create(:show, author: "Original Author")

    # Try to set author to empty string and cause validation failure
    attributes = FactoryBot.attributes_for(:show, author: "")
    attributes[:venue_id] = nil  # This will cause validation to fail

    put :update, params: { id: @show, show: attributes }

    assert_response :unprocessable_entity

    # The author field should be empty (normalized from empty string)
    assert_equal "", assigns(:show).author, "Author field should be empty when set to empty string"

    # The form should not crash and should render properly with empty author
    assert_response :unprocessable_entity
  end


  test "should destroy show" do
    @show = FactoryBot.create(:show, team_member_count: 0, picture_count: 0, review_count: 0, feedback_count: 0)

    assert_difference("Show.count", -1) do
      delete :destroy, params: { id: @show }

      assert_nil flash[:errors]
    end

    assert_redirected_to admin_shows_path
  end

  test "should update debt settings and create debts" do
    # Create show with known team members (all Directors, not capped)
    @show = FactoryBot.create(:show, start_date: start_of_year, end_date: start_of_year.advance(days: 7), team_member_count: 0)
    3.times do
      user = FactoryBot.create(:user)
      FactoryBot.create(:team_member, teamwork: @show, user: user, position: "Director")
    end

    debt_params = {
      maintenance_debt_amount: 1,
      maintenance_debt_start: Date.current.advance(days: 14),
      staffing_debt_amount: 2,
      staffing_debt_start: Date.current.advance(days: 14)
    }

    assert_difference "Admin::MaintenanceDebt.count", @show.team_members.count do
      assert_difference "Admin::StaffingDebt.count", @show.team_members.count * 2 do
        patch :update_debt_settings, params: { id: @show.slug, show: debt_params }
      end
    end

    assert_redirected_to admin_show_path(@show)
    assert flash[:success].first.include?("Debt settings saved")
  end

  test "should update debt settings without creating duplicate debts" do
    @show = FactoryBot.create(:show, start_date: start_of_year, end_date: start_of_year.advance(days: 7))

    debt_params = {
      maintenance_debt_amount: 1,
      maintenance_debt_start: Date.current.advance(days: 14),
      staffing_debt_amount: 1,
      staffing_debt_start: Date.current.advance(days: 14)
    }

    # First save creates debts
    patch :update_debt_settings, params: { id: @show.slug, show: debt_params }
    assert_redirected_to admin_show_path(@show)

    # Second save should not create more debts
    assert_no_difference "Admin::MaintenanceDebt.count" do
      assert_no_difference "Admin::StaffingDebt.count" do
        patch :update_debt_settings, params: { id: @show.slug, show: debt_params }
      end
    end

    assert_redirected_to admin_show_path(@show)
    # The last flash message should indicate no new debts were created
    assert_equal "Debt settings saved.", flash[:success].last
  end

  test "should not update debt settings for show outside academic year" do
    @show = FactoryBot.create(:show,
      start_date: start_of_year.advance(years: -2),
      end_date: start_of_year.advance(years: -2)
    )

    debt_params = {
      maintenance_debt_amount: 1,
      maintenance_debt_start: Date.current.advance(days: 14)
    }

    assert_no_difference "Admin::MaintenanceDebt.count" do
      patch :update_debt_settings, params: { id: @show.slug, show: debt_params }
    end

    assert_redirected_to admin_show_path(@show)
    assert_equal [ "Debt settings can only be configured for shows in the current academic year or later." ], flash[:error]
  end

  test "convert to season" do
    show = FactoryBot.create(:show, review_count: 0, feedback_count: 0)

    assert_difference("Show.count", -1) do
      assert_difference("Season.count", 1) do
        post :convert_to_season, params: { id: show }
      end
    end

    season = Season.find(show.id)

    assert_equal season.name, show.name
    assert_equal season.picture_ids, show.picture_ids
    assert_equal season.team_member_ids, show.team_member_ids
  end

  test "convert to workshop" do
    show = FactoryBot.create(:show, review_count: 0, feedback_count: 0)

    assert_difference("Show.count", -1) do
      assert_difference("Workshop.count", 1) do
        post :convert_to_workshop, params: { id: show }
      end
    end

    assert_equal [ "Converted the Show \"#{show.name}\" into the Workshop \"#{show.name}\"." ], flash[:success]

    workshop = Workshop.find(show.id)

    assert_equal workshop.name, show.name
    assert_equal workshop.picture_ids, show.picture_ids
    assert_equal workshop.team_member_ids, show.team_member_ids
  end

  # Assuming it also will not convert to a Workshop in this case.
  test "cannot convert to season when there is stuff attached" do
    show = FactoryBot.create(:show, feedback_count: 1)

    assert_no_difference("Show.count") do
      assert_no_difference("Season.count") do
        post :convert_to_season, params: { id: show }
      end
    end

    assert_equal [ "There are still attached feedbacks left. You cannot convert a show with one of these attached to prevent data loss." ], flash[:error]
  end

  test "cannot convert without permission" do
    sign_out @admin
    sign_in FactoryBot.create(:committee)

    show = FactoryBot.create(:show, review_count: 0, feedback_count: 0)

    post :convert_to_workshop, params: { id: show }

    assert_response 403
  end

  test "upload pictures using dropzone" do
    attributes = FactoryBot.attributes_for(:show)

    file_data = [ fixture_file_upload(Rails.root.join("test", "test.png"), "image/png") ]
    dropzone_data = {
      files: file_data,
      access_level: 0
    }

    assert_difference("Show.count") do
      assert_difference("Picture.count", file_data.size) do
        post :create, params: { show: attributes, dropzone_pictures: dropzone_data }
      end
    end

    assert assigns(:show).pictures.count, file_data.size

    assert(assigns(:show).pictures.all { |picture| picture.access_level == 0 })
    assert_redirected_to admin_show_path(assigns(:show))
  end

  test "raises error when dropzoning something random" do
    assert_raises ArgumentError do
      @show = FactoryBot.create(:show)
      attributes = FactoryBot.attributes_for(:show)

      dropzone_data = {
        files: [ "the", "content", "should", "not", "matter" ]
      }

      put :update, params: { id: @show, show: attributes, dropzone_finbar: dropzone_data }
    end
  end

  private

  def team_members_attributes(users)
    team_members_attributes = {}

    users.each_with_index do |user, count|
      team_members_attributes[count] = { position: "Viking#{count}", user_name_field: user.name, user_id: user.id, "_destroy"=>"false" }
    end

    team_members_attributes
  end
end
