require "test_helper"

class Admin::UserImportsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

  # Authorization tests

  test "should get new" do
    get :new
    assert_response :success
  end

  test "non-admin without absorb permission cannot access" do
    sign_out users(:admin)
    sign_in users(:member)

    get :new
    assert_response :forbidden
  end

  # Preview tests

  test "preview with valid paste data shows categorized results" do
    user = FactoryBot.create(:user, student_id: "s1234567")

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Test User\ts1234567\ttest@example.com
      New User\ts9999999\tnew@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert assigns(:import)
    assert_equal 2, assigns(:import).rows.size
  end

  test "preview with empty data redirects back with error" do
    post :preview, params: { paste_data: "" }

    assert_redirected_to new_admin_user_import_path
    assert flash[:error].present?
  end

  test "preview stores import data in session" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      New User\ts9999999\tnew@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert session[:pending_user_import].present?
  end

  # Confirm tests

  test "confirm without session data redirects with error" do
    post :confirm

    assert_redirected_to new_admin_user_import_path
    assert flash[:error].present?
  end

  test "confirm creates new user" do
    session[:pending_user_import] = {
      "exact_match_id" => [],
      "exact_match_email" => [],
      "fuzzy_match" => [],
      "create_new" => [
        { "row" => { "original_name" => "Brand New User", "first_name" => "Brand", "last_name" => "New User", "student_id" => "s9999999", "email" => "brandnew@example.com" }, "existing_user_id" => nil, "index" => 0 }
      ]
    }

    assert_difference "User.count", 1 do
      post :confirm, params: { actions: { "0" => "create" } }
    end

    assert_redirected_to admin_users_path
    new_user = User.find_by(email: "brandnew@example.com")
    assert new_user.present?
    assert_equal "s9999999", new_user.student_id
    assert flash[:success].any? { |msg| msg.include?("created") }
  end

  test "confirm skips when action is skip" do
    session[:pending_user_import] = {
      "exact_match_id" => [],
      "exact_match_email" => [],
      "fuzzy_match" => [],
      "create_new" => [
        { "row" => { "original_name" => "Skip User", "first_name" => "Skip", "last_name" => "User", "student_id" => "s8888888", "email" => "skip@example.com" }, "existing_user_id" => nil, "index" => 0 }
      ]
    }

    assert_no_difference "User.count" do
      post :confirm, params: { actions: { "0" => "skip" } }
    end

    assert_redirected_to admin_users_path
    assert flash[:success].any? { |msg| msg.include?("skipped") }
  end

  test "confirm links existing user when action is link" do
    user = FactoryBot.create(:user, student_id: "s1234567")

    session[:pending_user_import] = {
      "exact_match_id" => [
        { "row" => { "original_name" => "Test User", "first_name" => "Test", "last_name" => "User", "student_id" => "s1234567", "email" => "test@example.com" }, "existing_user_id" => user.id, "index" => 0 }
      ],
      "exact_match_email" => [],
      "fuzzy_match" => [],
      "create_new" => []
    }

    assert_no_difference "User.count" do
      post :confirm, params: { actions: { "0" => "link" } }
    end

    assert_redirected_to admin_users_path
    assert flash[:success].any? { |msg| msg.include?("linked") }
  end

  test "confirm generates placeholder email for new user without email" do
    session[:pending_user_import] = {
      "exact_match_id" => [],
      "exact_match_email" => [],
      "fuzzy_match" => [],
      "create_new" => [
        { "row" => { "original_name" => "No Email User", "first_name" => "No", "last_name" => "Email User", "student_id" => nil, "email" => nil }, "existing_user_id" => nil, "index" => 0 }
      ]
    }

    assert_difference "User.count", 1 do
      post :confirm, params: { actions: { "0" => "create" } }
    end

    new_user = User.find_by(first_name: "No", last_name: "Email User")
    assert new_user.present?, "New user should be created"
    assert new_user.email.match?(/\Aunknown_\w+@bedlamtheatre\.co\.uk\z/), "Email should be placeholder, got: #{new_user.email}"
  end

  test "confirm handles multiple actions in single import" do
    existing_user = FactoryBot.create(:user, student_id: "s1111111")

    session[:pending_user_import] = {
      "exact_match_id" => [
        { "row" => { "original_name" => "Existing User", "first_name" => "Existing", "last_name" => "User", "student_id" => "s1111111", "email" => "existing@example.com" }, "existing_user_id" => existing_user.id, "index" => 0 }
      ],
      "exact_match_email" => [],
      "fuzzy_match" => [],
      "create_new" => [
        { "row" => { "original_name" => "Create Me", "first_name" => "Create", "last_name" => "Me", "student_id" => "s2222222", "email" => "create@example.com" }, "existing_user_id" => nil, "index" => 1 },
        { "row" => { "original_name" => "Skip Me", "first_name" => "Skip", "last_name" => "Me", "student_id" => "s3333333", "email" => "skip@example.com" }, "existing_user_id" => nil, "index" => 2 }
      ]
    }

    assert_difference "User.count", 1 do
      post :confirm, params: {
        actions: {
          "0" => "link",
          "1" => "create",
          "2" => "skip"
        }
      }
    end

    assert User.find_by(email: "create@example.com").present?
    assert_nil User.find_by(email: "skip@example.com")
  end

  test "confirm clears session after processing" do
    session[:pending_user_import] = {
      "exact_match_id" => [],
      "exact_match_email" => [],
      "fuzzy_match" => [],
      "create_new" => []
    }

    post :confirm

    assert_nil session[:pending_user_import]
  end
end
