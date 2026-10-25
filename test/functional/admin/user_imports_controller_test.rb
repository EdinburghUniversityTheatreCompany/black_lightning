require "test_helper"

class Admin::UserImportsControllerTest < ActionController::TestCase
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
      Name\tStudent ID\tEmail
      Test User\ts1234567\ttest@example.com
      New User\ts9999999\tnew@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    assert_equal 2, assigns(:import).rows.size
    assert_select "a[href=?]", admin_user_path(matched)
    assert assigns(:cache_key).present?
    assert Rails.cache.read(assigns(:cache_key)).present?
  end

  test "preview shows a section for every bucket, each row with its decision" do
    FactoryBot.create(:user, first_name: "Ian", last_name: "Qbyid", student_id: "s1000002")
    FactoryBot.create(:user, first_name: "Emma", last_name: "Qbyemail", email: "emma.q@example.com")
    alex = FactoryBot.create(:user, first_name: "Alex", last_name: "Qzarquon", student_id: "s1000004")
    alexander = FactoryBot.create(:user, first_name: "Alexander", last_name: "Qzarquon")
    recent_show = FactoryBot.create(:show, start_date: Date.current)
    [ alex, alexander ].each { |user| recent_show.team_members.create!(user: user, position: "Crew") }

    tsv = <<~TSV
      Name\tStudent ID\tEmail
      Ian Qbyid\ts1000002\tian.q@example.com
      Emma Qbyemail\t\temma.q@example.com
      Alex Qzarquon\ts1000005\t
      Alex Qzarquon\t\t
      New Qperson\ts1000006\t
      No Qdetails\t\t
      Named Qemail\t\tnamed.q@example.com
    TSV

    post :preview, params: { paste_data: tsv }

    assert_response :success
    [ "Matched by ID", "Matched by Email", "Possible Matches (Review Required)", "New Users to Create" ].each do |title|
      assert_select "span", text: title
    end
    assert_select "input[type=hidden][name=?][value=link]", "actions[0]"
    assert_select "input[type=hidden][name=?][value=link]", "actions[1]"
    assert_select "input[type=radio][name=?][value=?][checked]", "actions[2]", "link_#{alex.id}"
    assert_select "input[type=radio][name=?][value=?]:not([checked])", "actions[3]", "link_#{alexander.id}"
    assert_select "input[type=radio][name=?]", "actions[3]", count: 4
    assert_select "input[type=radio][name=?][value=create][checked]", "actions[4]"
    assert_select "small", text: "(auto-generated)"
    assert_select "em", text: "(will generate placeholder)"
  end

  test "preview with empty data redirects back with error" do
    post :preview, params: { paste_data: "" }

    assert_redirected_to new_admin_user_import_path
    assert flash[:error].present?
  end

  test "confirm without cache data redirects with error" do
    post :confirm, params: { cache_key: "nonexistent_key" }

    assert_redirected_to new_admin_user_import_path
    assert flash[:error].present?
  end

  test "confirm generates placeholder email for new user without email" do
    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(
      cache_key,
      create_new: [
        import_entry(index: 0, original_name: "No Email User", first_name: "No", last_name: "Email User", student_id: nil, email: nil)
      ]
    )

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
    write_import_cache(
      cache_key,
      exact_match_id: [
        import_entry(index: 0, existing_user_id: existing_user.id, original_name: "Existing User", first_name: "Existing", last_name: "User", student_id: "s1111111", email: "existing@example.com")
      ],
      create_new: create_me_and_skip_me_entries
    )

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

    assert_redirected_to admin_users_path
    assert_equal [ "Import complete: 1 created, 1 linked to existing, 1 skipped" ], flash[:success]
    assert_equal "s2222222", User.find_by(email: "create@example.com").student_id
    assert_nil User.find_by(email: "skip@example.com")
  end

  test "confirm reports a row that cannot be created and carries on" do
    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(
      cache_key,
      create_new: [
        import_entry(index: 0, original_name: "First Twin", first_name: "First", last_name: "Twin", student_id: "s1111111", email: "twin@example.com"),
        import_entry(index: 1, original_name: "Second Twin", first_name: "Second", last_name: "Twin", student_id: "s2222222", email: "twin@example.com"),
        import_entry(index: 2, original_name: "Third Person", first_name: "Third", last_name: "Person", student_id: "s3333333", email: "third@example.com")
      ]
    )

    assert_difference "User.count", 2 do
      post :confirm, params: { cache_key: cache_key, actions: { "0" => "create", "1" => "create", "2" => "create" } }
    end

    assert_redirected_to admin_users_path
    assert_match(/2 created.*Errors: Second Twin/, flash[:success].first)
    assert User.exists?(email: "third@example.com")
  end

  test "confirm clears cache after processing" do
    cache_key = "user_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, create_new: [])

    post :confirm, params: { cache_key: cache_key }

    assert_nil Rails.cache.read(cache_key)
  end
end
