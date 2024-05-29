require 'test_helper'

class Archives::EventsControllerTest < ActionController::TestCase
  test 'should get index' do
    # Need at least one public event
    FactoryBot.create(:show, is_public: true)

    get :index
    assert_response :success

    assert assigns(:events).length > 0, "Make sure there is at least one event. Otherwise, you might need to create some."
  end

  test 'should ransack on event tags' do
    event = FactoryBot.create(:show, is_public: true)
    event_tag = event.event_tags.first

    assert event_tag.present?

    get :index, params: { q: { event_tags_id_eq: event_tag.id } }

    assert_response :success

    assert_equal 1, assigns(:events).length, "More events returned with the tag, even though the tag was created by factorybot."
    assert_equal event.id, assigns(:events).first.id, "The found event is not the event with the tag."
    assert_match event.name, response.body, "Event title not in index."
end
end
