require "test_helper"

class Admin::DuplicatesControllerTest < ActionController::TestCase
  setup do
    @admin = FactoryBot.create(:admin)
    sign_in @admin
  end

  test "should show duplicates with same student_id" do
    user1 = FactoryBot.create(:user, student_id: "s9999999", first_name: "Test", last_name: "DupeA")
    user2 = FactoryBot.create(:user, student_id: "s9999999", first_name: "Another", last_name: "DupeB")

    get :index
    assert_response :success

    duplicates = assigns(:duplicates)
    same_id_dups = duplicates[:same_id].select { |d| d[:id_value] == "s9999999" }
    assert_equal 1, same_id_dups.size
    assert_includes same_id_dups.first[:users], user1
    assert_includes same_id_dups.first[:users], user2
  end

  test "cached fuzzy pairs show the years each user was active" do
    active = FactoryBot.create(:user, first_name: "Anna", last_name: "Smith")
    idle = FactoryBot.create(:user, first_name: "Ana", last_name: "Smyth")
    show = FactoryBot.create(:show, start_date: Date.new(2023, 10, 1), end_date: Date.new(2023, 10, 5))
    TeamMember.create!(user: active, teamwork: show, position: "Actor")
    CachedDuplicate.create!(user1: active, user2: idle, bucket_type: "overlapping")

    get :index

    row = "tr#pair-#{[ active.id, idle.id ].min}-#{[ active.id, idle.id ].max}"
    assert_select row, text: /Active: 23\/24/
    assert_select row, text: /No activity recorded/
  end

  test "marking a cached pair as not duplicates removes it from the report" do
    user1 = FactoryBot.create(:user, first_name: "Anna", last_name: "Smith")
    user2 = FactoryBot.create(:user, first_name: "Ana", last_name: "Smyth")
    CachedDuplicate.create!(user1: user1, user2: user2, bucket_type: "no_overlap")

    post :mark_not_duplicate, params: { user_id: user2.id, other_user_id: user1.id }
    get :index

    assert_equal 0, CachedDuplicate.count
    assert_empty assigns(:duplicates)[:fuzzy_both_no_overlap]
  end

  test "should mark users as not duplicates and redirect for HTML" do
    user1 = FactoryBot.create(:user, first_name: "John", last_name: "UniqueTestSmith")
    user2 = FactoryBot.create(:user, first_name: "Jon", last_name: "UniqueTestSmith")

    assert_not user1.marked_not_duplicate?(user2)

    post :mark_not_duplicate, params: { user_id: user1.id, other_user_id: user2.id }

    assert_redirected_to admin_duplicates_path
    assert user1.reload.marked_not_duplicate?(user2)
  end

  test "should mark users as not duplicates and return turbo stream" do
    user1 = FactoryBot.create(:user, first_name: "John", last_name: "UniqueTestSmith2")
    user2 = FactoryBot.create(:user, first_name: "Jon", last_name: "UniqueTestSmith2")

    post :mark_not_duplicate, params: { user_id: user1.id, other_user_id: user2.id },
         format: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "pair-#{user1.id}-#{user2.id}"
    assert user1.reload.marked_not_duplicate?(user2)
  end

  test "non-admin without absorb permission cannot access" do
    sign_out @admin
    user = FactoryBot.create(:user)
    sign_in user

    get :index
    assert_response :forbidden
  end
end
