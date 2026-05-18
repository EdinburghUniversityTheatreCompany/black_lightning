require "test_helper"

##
# Tests for the public opportunity submission actions (new/create)
# added to GetInvolvedController.
##
class GetInvolvedOpportunitiesTest < ActionController::TestCase
  tests GetInvolvedController

  # ---------------------------------------------------------------------------
  # Routing
  # ---------------------------------------------------------------------------

  test "new route resolves correctly" do
    assert_routing "get_involved/opportunities/new",
                   controller: "get_involved", action: "new"
  end

  test "create route resolves correctly" do
    assert_routing({ method: "post", path: "get_involved/opportunities" },
                   controller: "get_involved", action: "create")
  end

  # ---------------------------------------------------------------------------
  # GET new
  # ---------------------------------------------------------------------------

  test "new redirects to login when not signed in" do
    get :new
    assert_redirected_to new_user_session_url
  end

  test "new returns 403 when user does not have create permission" do
    # The plain :user fixture has no roles and therefore no create permission.
    sign_in users(:user)
    get :new
    assert_response 403
  end

  test "new succeeds for a member with create permission" do
    sign_in users(:member)
    get :new
    assert_response :success
    assert_not_nil assigns(:opportunity)
    assert assigns(:opportunity).new_record?
  end

  # ---------------------------------------------------------------------------
  # POST create
  # ---------------------------------------------------------------------------

  test "create redirects to login when not signed in" do
    post :create, params: { opportunity: { title: "Test", description: "Desc", expiry_date: 1.week.from_now } }
    assert_redirected_to new_user_session_url
  end

  test "create returns 403 when user does not have create permission" do
    sign_in users(:user)
    post :create, params: { opportunity: { title: "Test", description: "Desc", expiry_date: 1.week.from_now } }
    assert_response 403
  end

  test "create saves an unapproved opportunity and redirects for a member" do
    sign_in users(:member)

    assert_difference "Opportunity.count", 1 do
      post :create, params: {
        opportunity: {
          title: "Backstage crew needed",
          description: "We need help behind the scenes.",
          expiry_date: 2.weeks.from_now,
          show_email: "0"
        }
      }
    end

    assert_redirected_to get_involved_opportunities_path
    assert_equal "Opportunity submitted! It will appear once reviewed.", flash[:notice]

    opportunity = Opportunity.last
    assert_equal "Backstage crew needed", opportunity.title
    assert_equal users(:member), opportunity.creator
    assert_equal false, opportunity.approved
  end

  test "create re-renders new with errors when params are invalid" do
    sign_in users(:member)

    assert_no_difference "Opportunity.count" do
      post :create, params: {
        opportunity: {
          title: "",
          description: "",
          expiry_date: nil
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create ignores any attempt to set approved to true" do
    sign_in users(:member)

    post :create, params: {
      opportunity: {
        title: "Sneaky opportunity",
        description: "Trying to self-approve.",
        expiry_date: 2.weeks.from_now,
        approved: true
      }
    }

    assert_equal false, Opportunity.last.approved
  end
end
