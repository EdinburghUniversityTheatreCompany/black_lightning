require "test_helper"

class Admin::MembershipImportsControllerTest < ActionController::TestCase
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
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s1234567\tTest User\t07/09/2025\tStudent\ttest@example.com
      s9999999\tNew User\t07/09/2025\tStudent\tnew@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert assigns(:import)
    assert_equal 2, assigns(:import).rows.size
  end

  test "preview with empty data redirects back with error" do
    post :preview, params: { paste_data: "" }

    assert_redirected_to new_admin_membership_import_path
    assert flash[:error].present?
  end

  test "preview stores import data in cache and sets cache_key" do
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s9999999\tNew User\t07/09/2025\tStudent\tnew@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert assigns(:cache_key).present?
    assert Rails.cache.read(assigns(:cache_key)).present?
  end

  # Confirm tests

  test "confirm without cache data redirects with error" do
    post :confirm, params: { cache_key: "nonexistent_key" }

    assert_redirected_to new_admin_membership_import_path
    assert flash[:error].present?
  end

  test "confirm activates user by student_id" do
    user = FactoryBot.create(:user, student_id: "s1234567")
    assert_not user.has_role?(:member)

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [
        { "row" => { "original_name" => "Test User", "student_id" => "s1234567", "email" => "test@example.com" }, "existing_user_id" => user.id, "index" => 0 }
      ],
      "activate_by_email" => [],
      "propose_merge" => [],
      "create_new" => []
    }, expires_in: 1.hour)

    post :confirm, params: { cache_key: cache_key, actions: { "0" => "activate" } }

    assert_redirected_to new_admin_membership_import_path
    assert user.reload.has_role?(:member)
    assert flash[:success].any? { |msg| msg.include?("activated") }
  end

  test "confirm creates new user" do
    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [],
      "activate_by_email" => [],
      "propose_merge" => [],
      "create_new" => [
        { "row" => { "original_name" => "Brand New User", "first_name" => "Brand", "last_name" => "New User", "student_id" => "s9999999", "email" => "brandnew@example.com" }, "existing_user_id" => nil, "index" => 0 }
      ]
    }, expires_in: 1.hour)

    assert_difference "User.count", 1 do
      post :confirm, params: { cache_key: cache_key, actions: { "0" => "create" } }
    end

    assert_redirected_to new_admin_membership_import_path
    new_user = User.find_by(email: "brandnew@example.com")
    assert new_user.present?
    assert new_user.has_role?(:member)
    assert_equal "s9999999", new_user.student_id
    assert flash[:success].any? { |msg| msg.include?("created") }
  end

  test "confirm skips when action is skip" do
    user = FactoryBot.create(:user, student_id: "s1234567")

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [
        { "row" => { "original_name" => "Test User", "student_id" => "s1234567", "email" => "test@example.com" }, "existing_user_id" => user.id, "index" => 0 }
      ],
      "activate_by_email" => [],
      "propose_merge" => [],
      "create_new" => []
    }, expires_in: 1.hour)

    post :confirm, params: { cache_key: cache_key, actions: { "0" => "skip" } }

    assert_redirected_to new_admin_membership_import_path
    assert_not user.reload.has_role?(:member)
    assert flash[:success].any? { |msg| msg.include?("skipped") }
  end

  test "confirm merges when action is merge" do
    user = FactoryBot.create(:user, first_name: "John", last_name: "Smith", email: "unknown_12345678@bedlamtheatre.co.uk")
    assert_not user.has_role?(:member)
    assert user.student_id.blank?

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [],
      "activate_by_email" => [],
      "propose_merge" => [
        { "row" => { "original_name" => "Johnny Smith", "first_name" => "Johnny", "last_name" => "Smith", "student_id" => "s1234567", "email" => "johnny@example.com" }, "existing_user_id" => user.id, "index" => 0 }
      ],
      "create_new" => []
    }, expires_in: 1.hour)

    post :confirm, params: { cache_key: cache_key, actions: { "0" => "merge" } }

    assert_redirected_to new_admin_membership_import_path
    user.reload
    assert user.has_role?(:member)
    assert_equal "s1234567", user.student_id
    assert_equal "johnny@example.com", user.email # Unknown email should be replaced
    assert flash[:success].any? { |msg| msg.include?("merged") }
  end

  test "confirm updates unknown email during activation" do
    user = FactoryBot.create(:user, student_id: "s1234567", email: "unknown_abcd1234@bedlamtheatre.co.uk")

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [
        { "row" => { "original_name" => "Test User", "student_id" => "s1234567", "email" => "real@example.com" }, "existing_user_id" => user.id, "index" => 0 }
      ],
      "activate_by_email" => [],
      "propose_merge" => [],
      "create_new" => []
    }, expires_in: 1.hour)

    post :confirm, params: { cache_key: cache_key, actions: { "0" => "activate" } }

    assert_equal "real@example.com", user.reload.email
  end

  test "confirm adds missing student_id during activation" do
    user = FactoryBot.create(:user, student_id: nil, email: "existing@example.com")

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [],
      "activate_by_email" => [
        { "row" => { "original_name" => "Test User", "student_id" => "s1234567", "email" => "existing@example.com" }, "existing_user_id" => user.id, "index" => 0 }
      ],
      "propose_merge" => [],
      "create_new" => []
    }, expires_in: 1.hour)

    post :confirm, params: { cache_key: cache_key, actions: { "0" => "activate" } }

    assert_equal "s1234567", user.reload.student_id
  end

  test "confirm generates placeholder email for new user without email" do
    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [],
      "activate_by_email" => [],
      "propose_merge" => [],
      "create_new" => [
        { "row" => { "original_name" => "No Email User", "first_name" => "No", "last_name" => "Email User", "student_id" => "s8888888", "email" => nil }, "existing_user_id" => nil, "index" => 0 }
      ]
    }, expires_in: 1.hour)

    assert_difference "User.count", 1 do
      post :confirm, params: { cache_key: cache_key, actions: { "0" => "create" } }
    end

    new_user = User.find_by(student_id: "s8888888")
    assert new_user.present?
    assert new_user.email.match?(/\Aunknown_\w+@bedlamtheatre\.co\.uk\z/)
  end

  test "confirm handles multiple actions in single import" do
    user_to_activate = FactoryBot.create(:user, student_id: "s1111111")

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [
        { "row" => { "original_name" => "Activate Me", "student_id" => "s1111111", "email" => "activate@example.com" }, "existing_user_id" => user_to_activate.id, "index" => 0 }
      ],
      "activate_by_email" => [],
      "propose_merge" => [],
      "create_new" => [
        { "row" => { "original_name" => "Create Me", "first_name" => "Create", "last_name" => "Me", "student_id" => "s2222222", "email" => "create@example.com" }, "existing_user_id" => nil, "index" => 1 },
        { "row" => { "original_name" => "Skip Me", "first_name" => "Skip", "last_name" => "Me", "student_id" => "s3333333", "email" => "skip@example.com" }, "existing_user_id" => nil, "index" => 2 }
      ]
    }, expires_in: 1.hour)

    assert_difference "User.count", 1 do
      post :confirm, params: {
        cache_key: cache_key,
        actions: {
          "0" => "activate",
          "1" => "create",
          "2" => "skip"
        }
      }
    end

    assert user_to_activate.reload.has_role?(:member)
    assert User.find_by(email: "create@example.com").present?
    assert_nil User.find_by(email: "skip@example.com")
  end

  test "confirm clears cache after processing" do
    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "already_active" => [],
      "activate_by_id" => [],
      "activate_by_email" => [],
      "propose_merge" => [],
      "create_new" => []
    }, expires_in: 1.hour)

    post :confirm, params: { cache_key: cache_key }

    assert_nil Rails.cache.read(cache_key)
  end
end
