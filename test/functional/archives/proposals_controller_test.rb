require 'test_helper'

class Archives::ProposalsControllerTest < ActionController::TestCase
  test 'index' do
    sign_in users(:admin)

    FactoryBot.create_list(:proposal, 10)

    get :index
    assert_response :success

    get :index, params: { commit: 'Random' }
    assert_redirected_to admin_proposals_proposal_path(assigns(:proposal))
  end
end
