require 'test_helper'

class ComplaintsControllerTest < ActionController::TestCase
  test 'should get new' do
    get :new
    assert_response :success

    assert_not_includes response.body, 'Comment'
    assert_not_includes response.body, 'Resolve'
  end


  test 'should create' do
    complaint = FactoryBot.attributes_for(:complaint)

    assert_difference('Complaint.count') do
      post :create, params: { complaint: complaint }
    end

    assert_redirected_to '/'
  end
end
