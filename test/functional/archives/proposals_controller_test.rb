require "test_helper"

class Archives::ProposalsControllerTest < ActionController::TestCase
  setup do
    sign_in users(:admin)

    @proposals = FactoryBot.create_list(:proposal, 3)
  end

  test "index" do
    get :index
    assert_response :success
  end

  test "index lists a call's successful proposals before its awaiting ones" do
    call = FactoryBot.create(:proposal_call)
    FactoryBot.create(:proposal, call: call, status: :awaiting_approval, show_title: "Awaiting Title")
    FactoryBot.create(:proposal, call: call, status: :successful, show_title: "Successful Title")

    get :index

    assert_operator response.body.index("Successful Title"), :<, response.body.index("Awaiting Title")
  end

  test "index with random" do
    get :index, params: { commit: "Random" }
    assert_redirected_to admin_proposals_proposal_path(assigns(:proposal))
  end

  test "index with a search for non-existent proposal" do
    get :index, params: { q: { show_title_cont: "this-show-title-will-never-exist" } }
    assert_response :success
  end
end
