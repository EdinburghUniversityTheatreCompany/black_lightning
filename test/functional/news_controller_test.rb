require 'test_helper'

class NewsControllerTest < ActionController::TestCase
  test 'should get index' do
    FactoryGirl.create_list(:news, 20)

    get :index
    assert_response :success
    assert_not_nil assigns(:news)
  end

  test 'should show news' do
    @news = FactoryGirl.create(:news)

    get :show, id: @news
    assert_response :success
  end
end
