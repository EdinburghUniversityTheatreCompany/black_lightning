require "test_helper"

class Admin::MembershipImportsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
  end

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

  test "preview renders the categorized rows and caches them" do
    matched = FactoryBot.create(:user, student_id: "s1234567")

    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s1234567\tTest User\t07/09/2025\tStudent\ttest@example.com
      s9999999\tNew User\t07/09/2025\tStudent\tnew@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert_equal 2, assigns(:import).rows.size
    assert_select "a[href=?]", admin_user_path(matched)
    assert assigns(:cache_key).present?
    assert Rails.cache.read(assigns(:cache_key)).present?
  end

  test "preview does not promise to add an ID the matched user already has" do
    FactoryBot.create(:user, student_id: "s1111111", email: "has.id@example.com")
    tsv = <<~TSV
      Student ID\tName\tDate Purchased\tMember Type\tPurchaser Email
      s2222222\tHas Id\t07/09/2025\tStudent\thas.id@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert_select "small", text: /will be added/, count: 0
  end

  test "preview with empty data redirects back with error" do
    post :preview, params: { paste_data: "" }

    assert_redirected_to new_admin_membership_import_path
    assert flash[:error].present?
  end

  test "confirm without cache data redirects with error" do
    post :confirm, params: { cache_key: "nonexistent_key" }

    assert_redirected_to new_admin_membership_import_path
    assert flash[:error].present?
  end

  test "activation fills a placeholder email and a missing student_id" do
    user = FactoryBot.create(:user, associate_id: "ASSOC1", student_id: nil, email: "unknown_abcd1234@bedlamtheatre.co.uk")

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    write_import_cache(
      cache_key,
      activate_by_id: [
        import_entry(index: 0, existing_user_id: user.id, original_name: "Test User", student_id: "s1234567", email: "real@example.com")
      ]
    )

    post :confirm, params: { cache_key: cache_key, actions: { "0" => "activate" } }

    user.reload
    assert_equal "real@example.com", user.email
    assert_equal "s1234567", user.student_id
  end

  test "confirm generates placeholder email for new user without email" do
    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    write_import_cache(
      cache_key,
      create_new: [
        import_entry(index: 0, original_name: "No Email User", first_name: "No", last_name: "Email User", student_id: "s8888888", email: nil)
      ]
    )

    assert_difference "User.count", 1 do
      post :confirm, params: { cache_key: cache_key, actions: { "0" => "create" } }
    end

    new_user = User.find_by(student_id: "s8888888")
    assert new_user.present?
    assert_match /\Aunknown_\w+@bedlamtheatre\.co\.uk\z/, new_user.email
  end

  test "confirm handles multiple actions in single import" do
    user_to_activate = FactoryBot.create(:user, student_id: "s1111111")

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    write_import_cache(
      cache_key,
      activate_by_id: [
        import_entry(index: 0, existing_user_id: user_to_activate.id, original_name: "Activate Me", student_id: "s1111111", email: "activate@example.com")
      ],
      create_new: create_me_and_skip_me_entries
    )

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

    assert_redirected_to new_admin_membership_import_path
    assert_equal [ "Import complete: 1 activated, 1 created, 1 skipped" ], flash[:success]
    assert user_to_activate.reload.has_role?(:member)
    created = User.find_by(email: "create@example.com")
    assert created.has_role?(:member)
    assert_equal "s2222222", created.student_id
    assert_nil User.find_by(email: "skip@example.com")
  end

  test "confirm clears cache after processing" do
    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, create_new: [])

    post :confirm, params: { cache_key: cache_key }

    assert_nil Rails.cache.read(cache_key)
  end

  test "confirm merges with selected user when action is merge_<id>" do
    user1 = FactoryBot.create(:user, first_name: "Alex", last_name: "Kerr", email: "unknown_aaa@bedlamtheatre.co.uk")
    user2 = FactoryBot.create(:user, first_name: "Alexander", last_name: "Kerr", email: "unknown_bbb@bedlamtheatre.co.uk")

    cache_key = "membership_import_test_#{SecureRandom.uuid}"
    write_import_cache(
      cache_key,
      propose_merge: [
        import_entry(index: 0, existing_user_ids: [ user1.id, user2.id ], original_name: "Alex Kerr", first_name: "Alex", last_name: "Kerr", student_id: "s1234567", email: "alex@example.com")
      ]
    )

    post :confirm, params: { cache_key: cache_key, actions: { "0" => "merge_#{user2.id}" } }

    assert_redirected_to new_admin_membership_import_path
    user2.reload
    assert user2.has_role?(:member)
    assert_equal "alex@example.com", user2.email
    assert_equal "s1234567", user2.student_id
    user1.reload
    assert_not user1.has_role?(:member)
  end
end
