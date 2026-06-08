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

  test "new succeeds for a logged-out visitor" do
    get :new
    assert_response :success
    assert_not_nil assigns(:opportunity)
    assert assigns(:opportunity).new_record?
  end

  test "new succeeds for a signed-in member" do
    sign_in users(:member)
    get :new
    assert_response :success
  end

  # ---------------------------------------------------------------------------
  # POST create
  # ---------------------------------------------------------------------------

  test "create saves an unapproved opportunity for a signed-in member" do
    sign_in users(:member)

    assert_difference "Opportunity.count", 1 do
      post :create, params: {
        opportunity: {
          title: "Backstage crew needed",
          description: "We need help behind the scenes.",
          expiry_date: 2.weeks.from_now
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

  test "create lets a logged-out visitor submit with submitter details, company and roles" do
    assert_difference "Opportunity.count", 1 do
      post :create, params: {
        opportunity: {
          description: "External crew call.",
          project: "Macbeth",
          expiry_date: 2.weeks.from_now,
          submitter_name: "Jane External",
          submitter_email: "jane.external@example.com",
          company_name: "Brand New Society",
          roles_attributes: { "0" => { position: "Stage Manager", category: "stage" } }
        }
      }
    end

    opportunity = Opportunity.last
    assert_nil opportunity.creator_id
    assert opportunity.external?
    assert_equal "Jane External", opportunity.submitter_name
    assert_equal "Brand New Society", opportunity.company&.name
    assert_equal [ "Stage Manager" ], opportunity.roles.map(&:position)
    assert_equal false, opportunity.approved
  end

  test "create rejects a logged-out submission without submitter details" do
    assert_no_difference "Opportunity.count" do
      post :create, params: {
        opportunity: { title: "No contact", description: "x", expiry_date: 2.weeks.from_now }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create silently drops a submission when the honeypot is filled" do
    assert_no_difference "Opportunity.count" do
      post :create, params: {
        opportunity: {
          title: "Spammy", description: "x", expiry_date: 2.weeks.from_now,
          submitter_name: "Bot", submitter_email: "bot@example.com",
          website_url: "http://spam.example.com"
        }
      }
    end

    assert_redirected_to get_involved_opportunities_path
  end

  test "create reuses an existing company case-insensitively instead of duplicating" do
    assert_no_difference "Company.count" do
      post :create, params: {
        opportunity: {
          title: "Reuse company", description: "x", expiry_date: 2.weeks.from_now,
          submitter_name: "Jane", submitter_email: "jane@example.com",
          company_name: companies(:gutter_theatre).name.upcase
        }
      }
    end

    assert_equal companies(:gutter_theatre), Opportunity.last.company
  end

  test "create re-renders for a logged-out submission that fails reCAPTCHA" do
    # Stop skipping reCAPTCHA in the test env; with no token in the request the gem
    # returns false without calling out to Google.
    original = Recaptcha.configuration.skip_verify_env.dup
    Recaptcha.configuration.skip_verify_env.delete("test")

    assert_no_difference "Opportunity.count" do
      post :create, params: {
        opportunity: {
          title: "Captcha fail", description: "x", expiry_date: 2.weeks.from_now,
          submitter_name: "Jane", submitter_email: "jane@example.com"
        }
      }
    end

    assert_response :unprocessable_entity
  ensure
    Recaptcha.configuration.skip_verify_env.replace(original)
  end

  test "create ignores submitter fields supplied by a signed-in member" do
    sign_in users(:member)

    post :create, params: {
      opportunity: {
        title: "Member submission", description: "x", expiry_date: 2.weeks.from_now,
        submitter_name: "Spoofed", submitter_email: "spoof@example.com"
      }
    }

    opportunity = Opportunity.last
    assert_equal users(:member), opportunity.creator
    assert_not opportunity.external?
    assert_nil opportunity.submitter_name
  end

  test "create gracefully handles an invalid enum value" do
    assert_no_difference "Opportunity.count" do
      post :create, params: {
        opportunity: {
          title: "Bad enum", description: "x", expiry_date: 2.weeks.from_now,
          submitter_name: "Jane", submitter_email: "jane@example.com",
          compensation_type: "not-a-real-value"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create re-renders new with errors when params are invalid" do
    sign_in users(:member)

    assert_no_difference "Opportunity.count" do
      post :create, params: {
        opportunity: { title: "", description: "", expiry_date: nil }
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

  # ---------------------------------------------------------------------------
  # GET opportunities (public listing, filtering, sorting)
  # ---------------------------------------------------------------------------

  test "opportunities lists only approved, unexpired opportunities" do
    get :opportunities
    assert_response :success

    assert_includes assigns(:opportunities), opportunities(:internal_project_opportunity)
    assert_not_includes assigns(:opportunities), opportunities(:expired_opportunity)
    assert_not_includes assigns(:opportunities), opportunities(:unapproved_opportunity)
  end

  test "opportunities sorts internal (EUTC) companies first" do
    get :opportunities

    listed = assigns(:opportunities).to_a
    internal_index = listed.index(opportunities(:internal_project_opportunity))
    external_index = listed.index(opportunities(:external_project_opportunity))

    assert internal_index < external_index, "internal company opportunities should be listed first"
  end

  test "opportunities filters by role category" do
    get :opportunities, params: { category: "stage" }

    assert_equal "stage", assigns(:selected_category)
    assert_includes assigns(:opportunities), opportunities(:internal_project_opportunity)
    assert_not_includes assigns(:opportunities), opportunities(:external_project_opportunity)
  end

  test "opportunities ignores an unknown category" do
    get :opportunities, params: { category: "not-a-category" }

    assert_nil assigns(:selected_category)
    assert_includes assigns(:opportunities), opportunities(:external_project_opportunity)
  end

  test "opportunities filters by company slug" do
    get :opportunities, params: { q: { company_slug_eq: companies(:gutter_theatre).slug } }

    assert_includes assigns(:opportunities), opportunities(:external_project_opportunity)
    assert_not_includes assigns(:opportunities), opportunities(:internal_project_opportunity)
  end

  test "opportunities filters by compensation type" do
    get :opportunities, params: { q: { compensation_type_eq: Opportunity.compensation_types[:paid] } }

    assert_includes assigns(:opportunities), opportunities(:external_project_opportunity)
    assert_not_includes assigns(:opportunities), opportunities(:internal_project_opportunity)
  end

  test "opportunities exposes the available categories for the tabs" do
    get :opportunities

    assert_includes assigns(:available_categories), "stage"
    assert_includes assigns(:available_categories), "lighting"
    assert_not_includes assigns(:available_categories), "acting"
  end
end
