require "test_helper"

class Admin::ShowCrewImportsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
    @show = FactoryBot.create(:show)
  end

  # Authorization tests

  test "should get new" do
    get :new, params: { show_id: @show.slug }
    assert_response :success
  end

  test "should work with Season event type" do
    season = FactoryBot.create(:season, slug: "bedfest-2026", name: "Bedfest 2026")

    get :new, params: { season_id: season.slug }
    assert_response :success
    assert_includes assigns(:title), "Bedfest 2026"
  end

  test "should work with Workshop event type" do
    workshop = FactoryBot.create(:workshop, slug: "lighting-workshop", name: "Lighting Workshop")

    get :new, params: { workshop_id: workshop.slug }
    assert_response :success
    assert_includes assigns(:title), "Lighting Workshop"
  end

  test "should return 404 for non-existent event" do
    get :new, params: { show_id: "non-existent-slug" }
    assert_response :not_found
  end

  test "non-admin without update permission cannot access" do
    sign_out users(:admin)
    sign_in users(:member)

    get :new, params: { show_id: @show.slug }
    assert_response :forbidden
  end

  # Preview tests

  test "preview with valid paste data shows categorized results" do
    user = FactoryBot.create(:user, student_id: "s1234567")

    tsv = <<~TSV
      Name\tStudent ID\tEmail\tPosition
      Test User\ts1234567\ttest@example.com\tDirector
      New User\ts9999999\tnew@example.com\tProducer
    TSV

    post :preview, params: { show_id: @show.slug, paste_data: tsv }

    assert_response :success
    assert assigns(:import)
    assert_equal 2, assigns(:import).rows.size
  end

  test "preview with empty data redirects back with error" do
    post :preview, params: { show_id: @show.slug, paste_data: "" }

    assert_redirected_to new_admin_show_show_crew_import_path(@show)
    assert flash[:error].present?
  end

  test "preview stores import data in cache and sets cache_key" do
    tsv = <<~TSV
      Name\tStudent ID\tEmail\tPosition
      New User\ts9999999\tnew@example.com\tDirector
    TSV

    post :preview, params: { show_id: @show.slug, paste_data: tsv }

    assert assigns(:cache_key).present?
    cached_data = Rails.cache.read(assigns(:cache_key))
    assert cached_data.present?
    assert_equal @show.id, cached_data[:event_id]
  end

  test "preview identifies existing team members" do
    user = FactoryBot.create(:user, student_id: "s1234567")
    @show.team_members.create!(user: user, position: "Producer")

    tsv = <<~TSV
      Name\tStudent ID\tEmail\tPosition
      Test User\ts1234567\ttest@example.com\tDirector
    TSV

    post :preview, params: { show_id: @show.slug, paste_data: tsv }

    assert_response :success
    assert assigns(:existing_team_members).present?
    assert assigns(:existing_team_members).key?(user.id)
    assert_equal "Producer", assigns(:existing_team_members)[user.id]["current_position"]
    assert_equal "Director", assigns(:existing_team_members)[user.id]["new_position"]
  end

  # Confirm tests

  test "confirm without cache data redirects with error" do
    post :confirm, params: { show_id: @show.slug, cache_key: "nonexistent_key" }

    assert_redirected_to new_admin_show_show_crew_import_path(@show)
    assert flash[:error].present?
  end

  test "confirm creates new user and adds to crew" do
    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "event_id" => @show.id,
      "categorized" => {
        "exact_match_id" => [],
        "exact_match_email" => [],
        "fuzzy_match" => [],
        "create_new" => [
          { "row" => { "original_name" => "New Director", "first_name" => "New", "last_name" => "Director", "student_id" => "s9999999", "email" => "new@example.com", "position" => "Director" }, "existing_user_id" => nil, "index" => 0 }
        ]
      },
      "existing_team_members" => {}
    }, expires_in: 1.hour)

    assert_difference [ "User.count", "@show.team_members.count" ], 1 do
      post :confirm, params: { show_id: @show.slug, cache_key: cache_key, actions: { "0" => "create" } }
    end

    assert_redirected_to admin_show_path(@show)
    new_user = User.find_by(email: "new@example.com")
    assert new_user.present?
    assert @show.team_members.exists?(user: new_user, position: "Director")
    assert flash[:success].any? { |msg| msg.include?("created") }
  end

  test "confirm adds existing user to crew" do
    user = FactoryBot.create(:user, student_id: "s1234567")

    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "event_id" => @show.id,
      "categorized" => {
        "exact_match_id" => [
          { "row" => { "original_name" => "Test User", "first_name" => "Test", "last_name" => "User", "student_id" => "s1234567", "email" => "test@example.com", "position" => "Producer" }, "existing_user_id" => user.id, "index" => 0 }
        ],
        "exact_match_email" => [],
        "fuzzy_match" => [],
        "create_new" => []
      },
      "existing_team_members" => {}
    }, expires_in: 1.hour)

    assert_no_difference "User.count" do
      assert_difference "@show.team_members.count", 1 do
        post :confirm, params: { show_id: @show.slug, cache_key: cache_key, actions: { "0" => "link" } }
      end
    end

    assert_redirected_to admin_show_path(@show)
    assert @show.team_members.exists?(user: user, position: "Producer")
  end

  test "confirm skips when action is skip" do
    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "event_id" => @show.id,
      "categorized" => {
        "exact_match_id" => [],
        "exact_match_email" => [],
        "fuzzy_match" => [],
        "create_new" => [
          { "row" => { "original_name" => "Skip User", "first_name" => "Skip", "last_name" => "User", "student_id" => "s8888888", "email" => "skip@example.com", "position" => "Director" }, "existing_user_id" => nil, "index" => 0 }
        ]
      },
      "existing_team_members" => {}
    }, expires_in: 1.hour)

    assert_no_difference [ "User.count", "@show.team_members.count" ] do
      post :confirm, params: { show_id: @show.slug, cache_key: cache_key, actions: { "0" => "skip" } }
    end

    assert_redirected_to admin_show_path(@show)
    assert flash[:success].any? { |msg| msg.include?("skipped") }
  end

  test "confirm merges positions for existing team member" do
    user = FactoryBot.create(:user, student_id: "s1234567")
    team_member = @show.team_members.create!(user: user, position: "Producer")

    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "event_id" => @show.id,
      "categorized" => {
        "exact_match_id" => [],
        "exact_match_email" => [],
        "fuzzy_match" => [],
        "create_new" => []
      },
      "existing_team_members" => {
        user.id.to_s => {
          "user_id" => user.id,
          "user_name" => user.name_or_email,
          "current_position" => "Producer",
          "new_position" => "Director",
          "index" => 0
        }
      }
    }, expires_in: 1.hour)

    post :confirm, params: { show_id: @show.slug, cache_key: cache_key, existing_actions: { user.id.to_s => "merge" } }

    assert_redirected_to admin_show_path(@show)
    team_member.reload
    assert_equal "Producer, Director", team_member.position
    assert flash[:success].any? { |msg| msg.include?("updated") }
  end

  test "confirm replaces position for existing team member" do
    user = FactoryBot.create(:user, student_id: "s1234567")
    team_member = @show.team_members.create!(user: user, position: "Producer")

    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "event_id" => @show.id,
      "categorized" => {
        "exact_match_id" => [],
        "exact_match_email" => [],
        "fuzzy_match" => [],
        "create_new" => []
      },
      "existing_team_members" => {
        user.id.to_s => {
          "user_id" => user.id,
          "user_name" => user.name_or_email,
          "current_position" => "Producer",
          "new_position" => "Director",
          "index" => 0
        }
      }
    }, expires_in: 1.hour)

    post :confirm, params: { show_id: @show.slug, cache_key: cache_key, existing_actions: { user.id.to_s => "replace" } }

    assert_redirected_to admin_show_path(@show)
    team_member.reload
    assert_equal "Director", team_member.position
  end

  test "confirm skips existing team member when action is skip" do
    user = FactoryBot.create(:user, student_id: "s1234567")
    team_member = @show.team_members.create!(user: user, position: "Producer")

    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "event_id" => @show.id,
      "categorized" => {
        "exact_match_id" => [],
        "exact_match_email" => [],
        "fuzzy_match" => [],
        "create_new" => []
      },
      "existing_team_members" => {
        user.id.to_s => {
          "user_id" => user.id,
          "user_name" => user.name_or_email,
          "current_position" => "Producer",
          "new_position" => "Director",
          "index" => 0
        }
      }
    }, expires_in: 1.hour)

    post :confirm, params: { show_id: @show.slug, cache_key: cache_key, existing_actions: { user.id.to_s => "skip" } }

    assert_redirected_to admin_show_path(@show)
    team_member.reload
    assert_equal "Producer", team_member.position # Unchanged
  end

  test "confirm clears cache after processing" do
    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "event_id" => @show.id,
      "categorized" => {
        "exact_match_id" => [],
        "exact_match_email" => [],
        "fuzzy_match" => [],
        "create_new" => []
      },
      "existing_team_members" => {}
    }, expires_in: 1.hour)

    post :confirm, params: { show_id: @show.slug, cache_key: cache_key }

    assert_nil Rails.cache.read(cache_key)
  end

  test "confirm rejects mismatched event_id" do
    other_show = FactoryBot.create(:show)

    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    Rails.cache.write(cache_key, {
      "event_id" => other_show.id, # Different show
      "categorized" => {
        "exact_match_id" => [],
        "exact_match_email" => [],
        "fuzzy_match" => [],
        "create_new" => []
      },
      "existing_team_members" => {}
    }, expires_in: 1.hour)

    post :confirm, params: { show_id: @show.slug, cache_key: cache_key }

    assert_redirected_to new_admin_show_show_crew_import_path(@show)
    assert flash[:error].present?
  end
end
