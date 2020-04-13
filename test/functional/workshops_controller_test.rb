require 'test_helper'

class WorkshopsControllerTest < ActionController::TestCase
  test 'should get index' do
    FactoryBot.create_list(:workshop, 10)

    get :index
    assert_response :success
    assert_not_nil assigns(:workshops)
  end

  test 'should get show' do
    @workshop = FactoryBot.create(:workshop)

    get :show, params: { id: @workshop}
    assert_response :success
  end
end
