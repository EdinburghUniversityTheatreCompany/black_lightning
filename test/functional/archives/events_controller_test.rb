require "test_helper"

class Archives::EventsControllerTest < ActionController::TestCase
  test "should get index" do
    # Need at least one public event
    FactoryBot.create(:show, is_public: true)

    get :index
    assert_response :success

    assert assigns(:events).length > 0, "Make sure there is at least one event. Otherwise, you might need to create some."
  end

  test "should ransack on event tags" do
    event = FactoryBot.create(:show, is_public: true, tag_count: 1)
    event_tag = event.event_tags.first

    assert event_tag.present?

    get :index, params: { q: { event_tags_id_eq: event_tag.id } }

    assert_response :success

    assert_equal 1, assigns(:events).length, "More events returned with the tag, even though the tag was created by factorybot."
    assert_equal event.id, assigns(:events).first.id, "The found event is not the event with the tag."
    assert_match event.name, response.body, "Event title not in index."
  end

  test "ransack on name filters the rendered collection" do
    match     = FactoryBot.create(:show, is_public: true, name: "Pericles Prince of Tyre")
    non_match = FactoryBot.create(:show, is_public: true, name: "Hamlet")

    get :index, params: { q: { name_cont: "pericles" } }

    assert_response :success
    assert_includes assigns(:events), match
    assert_not_includes assigns(:events), non_match
    assert_match match.name, response.body
    assert_no_match(/#{non_match.name}/, response.body)
  end

  test "responds to a turbo_stream request (live search)" do
    match     = FactoryBot.create(:show, is_public: true, name: "Pericles Prince of Tyre")
    non_match = FactoryBot.create(:show, is_public: true, name: "Hamlet")

    get :index, params: { q: { name_cont: "pericles" } }, format: :turbo_stream

    assert_response :success
    # Regression: the index used to return `head :ok` (empty body) for turbo_stream
    # because no archives/events/_index_results partial existed, so live search did nothing.
    assert_match "index-results", response.body
    assert_includes assigns(:events), match
    assert_not_includes assigns(:events), non_match
    assert_match match.name, response.body
    assert_no_match(/#{non_match.name}/, response.body)
  end
end
