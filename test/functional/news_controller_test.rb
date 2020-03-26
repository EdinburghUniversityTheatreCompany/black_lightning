require 'test_helper'

class NewsControllerTest < ActionController::TestCase
  test 'should get index' do
    FactoryBot.create_list(:news, 20)

    get :index
    assert_response :success
    assert_not_nil assigns(:news)
  end

  test 'should show news' do
    @news = FactoryBot.create(:news)

    get :show, params: { id: @news}
    assert_response :success
  end
end
