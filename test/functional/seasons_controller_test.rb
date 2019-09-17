require 'test_helper'

class SeasonsControllerTest < ActionController::TestCase
  test 'should get show' do
    @season = FactoryGirl.create(:season, show_count: 10)

    get :show, params: { id: @season}
    assert_response :success
  end
end
