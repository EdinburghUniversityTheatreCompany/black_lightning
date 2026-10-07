require "test_helper"

class Admin::ShowCrewImportsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)
    @show = FactoryBot.create(:show)
  end

  test "should get new for a show, season or workshop" do
    { show_id: @show, season_id: FactoryBot.create(:season), workshop_id: FactoryBot.create(:workshop) }.each do |param, event|
      get :new, params: { param => event.slug }
      assert_response :success
      assert_includes assigns(:title), event.name
      assert_select "a[href=?]", Rails.application.routes.url_helpers.polymorphic_path([ :admin, event ])
    end
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

  test "confirm without cache data redirects with error" do
    post :confirm, params: { show_id: @show.slug, cache_key: "nonexistent_key" }

    assert_redirected_to new_admin_show_show_crew_import_path(@show)
    assert flash[:error].present?
  end

  test "confirm creates new user and adds to crew" do
    cache_key = write_crew_cache(create_new: [
      import_entry(index: 0, original_name: "New Director", first_name: "New", last_name: "Director", student_id: "s9999999", email: "new@example.com", position: "Director")
    ])

    assert_difference [ "User.count", "@show.team_members.count" ], 1 do
      post :confirm, params: { show_id: @show.slug, cache_key: cache_key, actions: { "0" => "create" } }
    end

    assert_redirected_to admin_show_path(@show)
    new_user = User.find_by(email: "new@example.com")
    assert new_user.present?
    assert @show.team_members.exists?(user: new_user, position: "Director")
    assert flash[:success].any? { |msg| msg.include?("created") }
  end

  test "confirm names a row that cannot be created and still processes the others" do
    FactoryBot.create(:user, email: "taken@example.com")
    cache_key = write_crew_cache(create_new: [
      import_entry(index: 0, original_name: "Good Person", first_name: "Good", last_name: "Person", student_id: "s9999999", email: "good@example.com", position: "Director"),
      import_entry(index: 1, original_name: "Clash Person", first_name: "Clash", last_name: "Person", student_id: "s8888888", email: "taken@example.com", position: "Producer"),
      import_entry(index: 2, original_name: "Last Person", first_name: "Last", last_name: "Person", student_id: "s7777777", email: "last@example.com", position: "Designer")
    ])

    assert_difference "User.count", 2 do
      post :confirm, params: { show_id: @show.slug, cache_key: cache_key, actions: { "0" => "create", "1" => "create", "2" => "create" } }
    end

    assert_redirected_to admin_show_path(@show)
    assert_equal %w[Designer Director], @show.team_members.pluck(:position).sort
    assert flash[:success].any? { |msg| msg.include?("2 users created") && msg.include?("Errors: Clash Person:") }
  end

  test "confirm adds existing user to crew" do
    user = FactoryBot.create(:user, student_id: "s1234567")
    cache_key = write_crew_cache(exact_match_id: [
      import_entry(index: 0, existing_user_id: user.id, original_name: "Test User", first_name: "Test", last_name: "User", student_id: "s1234567", email: "test@example.com", position: "Producer")
    ])

    assert_no_difference "User.count" do
      assert_difference "@show.team_members.count", 1 do
        post :confirm, params: { show_id: @show.slug, cache_key: cache_key, actions: { "0" => "link" } }
      end
    end

    assert_redirected_to admin_show_path(@show)
    assert @show.team_members.exists?(user: user, position: "Producer")
  end

  test "confirm skips when action is skip" do
    cache_key = write_crew_cache(create_new: [
      import_entry(index: 0, original_name: "Skip User", first_name: "Skip", last_name: "User", student_id: "s8888888", email: "skip@example.com", position: "Director")
    ])

    assert_no_difference [ "User.count", "@show.team_members.count" ] do
      post :confirm, params: { show_id: @show.slug, cache_key: cache_key, actions: { "0" => "skip" } }
    end

    assert_redirected_to admin_show_path(@show)
    assert flash[:success].any? { |msg| msg.include?("skipped") }
  end

  test "confirm merges, replaces or keeps an existing team member's position" do
    { "merge" => "Producer / Director", "replace" => "Director", "skip" => "Producer" }.each do |action, expected|
      user, team_member, cache_key = setup_existing_team_member_cache

      post :confirm, params: { show_id: @show.slug, cache_key:, existing_actions: { user.id.to_s => action } }

      assert_redirected_to admin_show_path(@show)
      assert_equal expected, team_member.reload.position, action
    end
  end

  test "confirm counts an existing team member skipped once" do
    user, _team_member, cache_key = setup_existing_team_member_cache(on_team_row: true)

    post :confirm, params: { show_id: @show.slug, cache_key:, existing_actions: { user.id.to_s => "skip" } }

    assert flash[:success].any? { |msg| msg.include?("positions updated, 1 skipped") }
  end

  test "confirm redirects to the workshop's own page" do
    workshop = FactoryBot.create(:workshop)
    cache_key = write_crew_cache(event_id: workshop.id)

    post :confirm, params: { show_id: workshop.slug, cache_key: }

    assert_redirected_to admin_workshop_path(workshop)
  end

  test "confirm clears cache after processing" do
    cache_key = write_crew_cache

    post :confirm, params: { show_id: @show.slug, cache_key: cache_key }

    assert_nil Rails.cache.read(cache_key)
  end

  test "confirm rejects mismatched event_id" do
    cache_key = write_crew_cache(event_id: FactoryBot.create(:show).id)

    post :confirm, params: { show_id: @show.slug, cache_key: cache_key }

    assert_redirected_to new_admin_show_show_crew_import_path(@show)
    assert flash[:error].present?
  end

  test "confirm adds selected user to crew when action is link_<id>" do
    user1 = FactoryBot.create(:user, first_name: "Alex", last_name: "Kerr")
    user2 = FactoryBot.create(:user, first_name: "Alexander", last_name: "Kerr")
    cache_key = write_crew_cache(fuzzy_match: [
      import_entry(index: 0, existing_user_ids: [ user1.id, user2.id ], original_name: "Alex Kerr", first_name: "Alex", last_name: "Kerr", student_id: nil, email: nil, position: "Director")
    ])

    assert_difference("TeamMember.count", 1) do
      post :confirm, params: { show_id: @show.slug, cache_key: cache_key, actions: { "0" => "link_#{user2.id}" } }
    end

    assert_redirected_to admin_show_path(@show)
    assert @show.team_members.find_by(user_id: user2.id).present?
    assert_equal "Director", @show.team_members.find_by(user_id: user2.id).position
    assert_nil @show.team_members.find_by(user_id: user1.id)
  end

  private

  def write_crew_cache(event_id: @show.id, existing: {}, **buckets)
    cache_key = "crew_import_test_#{SecureRandom.uuid}"
    write_import_cache(cache_key, { "event_id" => event_id, "categorized" => user_import_buckets(**buckets), "existing_team_members" => existing })
    cache_key
  end

  # A "Producer" on @show whose cached import row proposes "Director". Returns [user, team_member, cache_key].
  # on_team_row also caches the exact-match row the preview leaves out for someone already on the team.
  def setup_existing_team_member_cache(on_team_row: false)
    user = FactoryBot.create(:user, student_id: "s1234567")
    team_member = @show.team_members.create!(user: user, position: "Producer")
    existing = { user.id.to_s => { "user_name" => user.name_or_email, "current_position" => "Producer", "new_position" => "Director" } }
    exact = on_team_row ? [ import_entry(index: 0, existing_user_id: user.id, student_id: "s1234567", position: "Director") ] : []

    [ user, team_member, write_crew_cache(existing:, exact_match_id: exact) ]
  end
end
