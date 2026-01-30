require "test_helper"

class Admin::DuplicatesControllerTest < ActionController::TestCase
  setup do
    @admin = FactoryBot.create(:admin)
    sign_in @admin
  end

  test "should get index" do
    get :index
    assert_response :success
    assert_not_nil assigns(:duplicates)
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

  test "should mark users as not duplicates" do
    user1 = FactoryBot.create(:user, first_name: "John", last_name: "UniqueTestSmith")
    user2 = FactoryBot.create(:user, first_name: "Jon", last_name: "UniqueTestSmith")

    assert_not user1.marked_not_duplicate?(user2)

    post :mark_not_duplicate, params: { user_id: user1.id, other_user_id: user2.id }

    assert_redirected_to admin_duplicates_path
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
