require 'test_helper'

class GetInvolvedControllerTest < ActionController::TestCase
  test 'should get index' do
    get :index
    assert_response :success
  end

  test 'should get opportunities' do
    FactoryGirl.create_list(:opportunity, 10)

    get :opportunities
    assert_response :success
    assert_not_nil assigns(:opportunities)
  end
end
