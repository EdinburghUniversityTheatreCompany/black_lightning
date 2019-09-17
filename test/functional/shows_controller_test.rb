require 'test_helper'

class ShowsControllerTest < ActionController::TestCase
  test 'should get index' do
    FactoryGirl.create_list(:show, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:shows)
  end

  test 'should get show' do
    @show = FactoryGirl.create(:show)

    get :show, params: { id: @show}
    assert_response :success
  end
end
