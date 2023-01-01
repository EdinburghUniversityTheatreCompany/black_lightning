require 'test_helper'

class VenuesControllerTest < ActionController::TestCase
  setup do
    @venue = venues(:one)
  end

  test 'should get index' do
    get :index
    assert_response :success
    assert_not_nil assigns(:venues)
  end

  test 'should show venue' do
    get :show, params: { id: @venue }
    assert_response :success
  end

  test 'should show venue without location specified' do
    get :show, params: { id: venues(:roxy)}
    assert_response :success
  end
end
