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

  test "show warns when the opportunity's company is unreviewed" do
    @opportunity.update!(company: companies(:unreviewed_company))

    get :show, params: { id: @opportunity }

    assert_response :success
    assert_match "hasn't been checked", response.body
    assert_match companies(:unreviewed_company).name, response.body
  end

  test "show does not warn when the company is reviewed" do
    @opportunity.update!(company: companies(:gutter_theatre))

    get :show, params: { id: @opportunity }

    assert_no_match "hasn't been checked", response.body
  end

  test "should create opportunity with company and nested roles" do
    attributes = FactoryBot.attributes_for(:opportunity).merge(
      company_name: companies(:gutter_theatre).name,
      project: "Eurydice",
      author: "Sarah Ruhl",
      roles_attributes: {
        "0" => { position: "Stage Manager", department_name: "Stage Management", ordering: "0" },
        "1" => { position: "Sound Technician", department_name: "Sound", ordering: "1" }
      }
    )

    assert_difference("Opportunity.count") do
      assert_difference("OpportunityRole.count", 2) do
        post :create, params: { opportunity: attributes }
      end
    end

    opportunity = assigns(:opportunity)
    assert_equal companies(:gutter_theatre), opportunity.company
    assert_equal "Eurydice", opportunity.project
    assert_equal "Sarah Ruhl", opportunity.author
    assert_equal %w[Stage\ Manager Sound\ Technician], opportunity.roles.order(:ordering).map(&:position)
  end

  test "blank role rows are dropped instead of failing validation" do
    attributes = FactoryBot.attributes_for(:opportunity).merge(
      roles_attributes: {
        "0" => { position: "Stage Manager", department_name: "Stage Management" },
        "1" => { position: "", department_name: "Other" }  # accidental empty row
      }
    )

    assert_difference("Opportunity.count") do
      assert_difference("OpportunityRole.count", 1) do
        post :create, params: { opportunity: attributes }
      end
    end

    assert_redirected_to admin_opportunity_path(assigns(:opportunity))
    assert_equal [ "Stage Manager" ], assigns(:opportunity).roles.map(&:position)
  end

  test "should show an external (creator-less) opportunity" do
    external = opportunities(:external_project_opportunity)
    assert_nil external.creator_id

    get :show, params: { id: external }
    assert_response :success
  end

  test "manager can attribute an opportunity to an external submitter" do
    attributes = FactoryBot.attributes_for(:opportunity).merge(
      submitter_name: "Jane External",
      submitter_email: "jane.external@example.com"
    )

    post :create, params: { opportunity: attributes }

    opportunity = assigns(:opportunity)
    assert_nil opportunity.creator_id, "creator should not be forced to current_user when a submitter is given"
    assert opportunity.external?
    assert_equal "Jane External", opportunity.submitter_name
  end

  test "manager can attribute an opportunity to a different user" do
    other = FactoryBot.create(:member)
    attributes = FactoryBot.attributes_for(:opportunity).merge(creator_id: other.id)

    post :create, params: { opportunity: attributes }

    assert_equal other.id, assigns(:opportunity).creator_id
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

  test "approving emails the submitter" do
    @opportunity.update!(approved: false)

    assert_enqueued_email_with OpportunityMailer, :approved, args: [ @opportunity, "Welcome aboard" ], queue: "mailers" do
      put :approve, params: { id: @opportunity, approval_note: "Welcome aboard" }
    end
  end

  test "rejecting emails the submitter" do
    @opportunity.update!(approved: true)

    assert_enqueued_email_with OpportunityMailer, :rejected, args: [ @opportunity, "Not this time" ], queue: "mailers" do
      put :reject, params: { id: @opportunity, approval_note: "Not this time" }
    end
  end

  test "approving does not email when there is no recipient" do
    opportunity = FactoryBot.create(:opportunity, approved: false)
    opportunity.update_columns(creator_id: nil, submitter_name: "Someone", submitter_email: nil)

    assert_no_enqueued_emails do
      put :approve, params: { id: opportunity }
    end
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
