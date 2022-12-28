require 'test_helper'

# These tests are not very comprehensive, but they will test if the pages load.
class Admin::DashboardControllerTest < ActionController::TestCase
  setup do
    @user = users(:admin)
    sign_in @user
  end

  test 'should get index' do
    get :index
    assert_response :success
  end

  # This is pretty much covered by the test for debts#show
  test 'debt widget' do
    assert_widget_does_not_error 'debt'
    assert_match "You are #{@user.debt_message_suffix}", response.body

    # Check if it renders the debts@show page
    assert_match 'not associated with any Debt', response.body
  end

  test 'news widget' do
    assert_widget_does_not_error 'news'
    assert_match 'There is no news', response.body

    FactoryBot.create_list(:news, 10)

    assert_widget_does_not_error 'news'
    news = News.current.first
    assert_match news.title, response.body
    assert_match news.body[0..70], response.body
  end

  test 'shows widget' do
    assert_widget_does_not_error 'shows'
    assert_match 'There are no upcoming shows', response.body

    FactoryBot.create_list(:show, 3)
    FactoryBot.create(:show, end_date: Date.current.advance(days: 1))
    assert_widget_does_not_error 'shows'
    assert_match Show.future.first.name, response.body
  end

  test 'proposals widget' do
    assert_widget_does_not_error 'proposals'
    assert_match 'There are no open proposal calls.', response.body

    call = FactoryBot.create(:proposal_call)

    assert_widget_does_not_error 'proposals'
    assert_match call.name, response.body
  end

  test 'resources widget' do
    assert_widget_does_not_error 'resources'
  end

  test 'staffings widget' do
    assert_widget_does_not_error 'staffings'
    assert_match 'There are no upcoming staffing slots.', response.body

    FactoryBot.create_list(:staffing, 10)

    assert_widget_does_not_error 'staffings'
    assert_match Admin::Staffing.future.first.show_title, response.body
  end

  test 'card number widget' do
    assert_widget_does_not_error 'card_number'
  end

  test 'committee_staffing widget' do
    assert_widget_does_not_error 'committee_staffing'
    assert_match 'Displays the amount of committee rep slots', response.body

    FactoryBot.create_list(:committee, 10)
    extra_committee = FactoryBot.create(:committee, first_name: 'Dennis the Donkey')

    assert_widget_does_not_error 'committee_staffing'
    assert_match extra_committee.first_name, response.body
  end

  test 'opportunities widget' do
    FactoryBot.create_list(:opportunity, 7)
    assert_widget_does_not_error 'opportunities'
  end

  test 'non-existent widget' do
    get :widget, params: { widget_name: 'Hexagons and Pineapples' }
    assert_match 'There is no widget with the name "Hexagons and Pineapples"', response.body
  end

  private

  def assert_widget_does_not_error(widget_name)
    get :widget, params: { widget_name: widget_name }

    assert_no_match 'There was an error rendering the widget', response.body
    assert_no_match 'Widget Not Found', response.body

    assert_response :success
  end
end
