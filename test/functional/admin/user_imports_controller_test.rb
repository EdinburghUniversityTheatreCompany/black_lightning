require "test_helper"

class Admin::UserImportsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
    ActionController::Base.perform_caching = true
    Rails.cache.clear
  end

  teardown do
    ActionController::Base.perform_caching = false
    Rails.cache.clear
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

  test "preview stores import data in cache and sets cache_key" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail
      New User\ts9999999\tnew@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert assigns(:cache_key).present?
    assert Rails.cache.read(assigns(:cache_key)).present?
  end

  # Confirm tests

  test "confirm without cache data redirects with error" do
    post :confirm, params: { cache_key: "nonexistent_key" }

    assert_redirected_to new_admin_user_import_path
    assert flash[:error].present?
  end

  test "confirm creates new user" do
    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, user_import_buckets(
      create_new: [
        import_entry(index: 0, original_name: "Brand New User", first_name: "Brand", last_name: "New User", student_id: "s9999999", email: "brandnew@example.com")
      ]
    ))

    assert_difference "User.count", 1 do
      post :confirm, params: { cache_key: cache_key, actions: { "0" => "create" } }
    end

    assert_redirected_to admin_users_path
    new_user = User.find_by(email: "brandnew@example.com")
    assert new_user.present?
    assert_equal "s9999999", new_user.student_id
    assert flash[:success].any? { |msg| msg.include?("created") }
  end

  test "confirm skips when action is skip" do
    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, user_import_buckets(
      create_new: [
        import_entry(index: 0, original_name: "Skip User", first_name: "Skip", last_name: "User", student_id: "s8888888", email: "skip@example.com")
      ]
    ))

    assert_no_difference "User.count" do
      post :confirm, params: { cache_key: cache_key, actions: { "0" => "skip" } }
    end

    assert_redirected_to admin_users_path
    assert flash[:success].any? { |msg| msg.include?("skipped") }
  end

  test "confirm links existing user when action is link" do
    user = FactoryBot.create(:user, student_id: "s1234567")

    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, user_import_buckets(
      exact_match_id: [
        import_entry(index: 0, existing_user_id: user.id, original_name: "Test User", first_name: "Test", last_name: "User", student_id: "s1234567", email: "test@example.com")
      ]
    ))

    assert_no_difference "User.count" do
      post :confirm, params: { cache_key: cache_key, actions: { "0" => "link" } }
    end

    assert_redirected_to admin_users_path
    assert flash[:success].any? { |msg| msg.include?("linked") }
  end

  test "confirm generates placeholder email for new user without email" do
    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, user_import_buckets(
      create_new: [
        import_entry(index: 0, original_name: "No Email User", first_name: "No", last_name: "Email User", student_id: nil, email: nil)
      ]
    ))

    assert_difference "User.count", 1 do
      post :confirm, params: { cache_key: cache_key, actions: { "0" => "create" } }
    end

    new_user = User.find_by(first_name: "No", last_name: "Email User")
    assert new_user.present?, "New user should be created"
    assert_match /\Aunknown_\w+@bedlamtheatre\.co\.uk\z/, new_user.email, "Email should be placeholder, got: #{new_user.email}"
  end

  test "confirm handles multiple actions in single import" do
    existing_user = FactoryBot.create(:user, student_id: "s1111111")

    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, user_import_buckets(
      exact_match_id: [
        import_entry(index: 0, existing_user_id: existing_user.id, original_name: "Existing User", first_name: "Existing", last_name: "User", student_id: "s1111111", email: "existing@example.com")
      ],
      create_new: create_me_and_skip_me_entries
    ))

    assert_difference "User.count", 1 do
      post :confirm, params: {
        cache_key: cache_key,
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

  test "confirm clears cache after processing" do
    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, user_import_buckets)

    post :confirm, params: { cache_key: cache_key }

    assert_nil Rails.cache.read(cache_key)
  end
end
