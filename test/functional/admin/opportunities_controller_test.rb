require "test_helper"

class Admin::OpportunitiesControllerTest < ActionController::TestCase
  setup do
    @user = users(:admin)
    sign_in @user
    @opportunity = FactoryBot.create(:opportunity, approved: false)
  end

  test "should get index" do
    FactoryBot.create_list(:opportunity, 3)

    get :index
    assert_response :success
    assert_not_nil assigns(:opportunities)
  end

  test "should get show" do
    get :show, params: { id: @opportunity }
    assert_response :success
  end

  test "should get new" do
    get :new
    assert_response :success
  end

  test "should create opportunity" do
    attributes = FactoryBot.attributes_for(:opportunity, approved: true, approver: @user)

    assert_difference("Opportunity.count") do
      post :create, params: { opportunity: attributes }
    end

    assert_not assigns(:opportunity).approved
    assert_nil assigns(:opportunity).approver

    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end

  test "should not create invalid opportunity" do
    attributes = FactoryBot.attributes_for(:opportunity, title: nil)

    assert_no_difference("Opportunity.count") do
      post :create, params: { opportunity: attributes }
    end

    assert_response :unprocessable_entity
  end

  test "should get edit" do
    get :edit, params: { id: @opportunity }
    assert_response :success
  end

  test "should update opportunity with approval permission" do
    @opportunity.approved = true
    @opportunity.approver = User.all.first
    @opportunity.save

    ##
    # NOTE IF THIS TEST FAILS #
    # Try changing approved to true in the attributes definition.
    # If the test no longer fails when approved,
    # that means that the user can change the approval through the update method.
    # There is probably something wrong with the params method.
    ##
    attributes = FactoryBot.attributes_for(:opportunity, approved: false)

    put :update, params: { id: @opportunity, opportunity: attributes }

    assert assigns(:opportunity).approved
    assert_equal @user, assigns(:opportunity).approver

    assert_equal attributes[:description], assigns(:opportunity).description

    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end

  test "should update opportunity without approval permission" do
    sign_in FactoryBot.create(:committee)

    @opportunity.approved = true
    @opportunity.save

    attributes = FactoryBot.attributes_for(:opportunity, approved: true)

    put :update, params: { id: @opportunity, opportunity: attributes }

    assert_not assigns(:opportunity).approved
    assert_nil assigns(:opportunity).approver

    assert_equal attributes[:description], assigns(:opportunity).description

    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end

  test "should not update invalid opportunity" do
    original_description = @opportunity.description
    attributes = FactoryBot.attributes_for(:opportunity, description: nil)

    put :update, params: { id: @opportunity, opportunity: attributes }

    @opportunity.reload
    assert_equal original_description, @opportunity.description

    assert_response :unprocessable_entity
  end

  test "should destroy opportunity" do
    assert_difference("Opportunity.count", -1) do
      delete :destroy, params: { id: @opportunity }
    end

    assert_redirected_to admin_opportunities_path
  end

  test "should approve opportunity" do
    @opportunity.approved = false
    @opportunity.approver = nil
    @opportunity.save

    put :approve, params: { id: @opportunity }

    assert assigns(:opportunity).approved
    assert_equal @user, assigns(:opportunity).approver

    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end

  test "should reject opportunity" do
    @opportunity.approved = true
    @opportunity.save

    put :reject, params: { id: @opportunity }

    assert_not assigns(:opportunity).approved
    assert_nil assigns(:opportunity).approver

    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
  end
end
