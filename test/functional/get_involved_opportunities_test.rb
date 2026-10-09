require "test_helper"

class GetInvolvedOpportunitiesTest < ActionController::TestCase
  tests GetInvolvedController

  test "new succeeds for a signed-in member, with image upload in the description editor" do
    sign_in users(:member)
    get :new
    assert_response :success
    assert_select "[data-markdown-editor-upload-url-value]"
  end

  test "new offers a logged-out visitor no image upload, which needs sign-in" do
    get :new
    assert_response :success
    assert_select "[data-controller='markdown-editor']"
    assert_select "[data-markdown-editor-upload-url-value]", false
  end

  test "a member's submission is attributed to them and unapproved, ignoring approved and submitter params" do
    sign_in users(:member)

    assert_difference "Opportunity.count", 1 do
      post :create, params: {
        opportunity: {
          title: "Backstage crew needed", description: "We need help behind the scenes.",
          expiry_date: 2.weeks.from_now, approved: true,
          submitter_name: "Spoofed", submitter_email: "spoof@example.com"
        }
      }
    end

    assert_redirected_to get_involved_opportunities_path
    assert_equal "Opportunity submitted! It will appear once reviewed.", flash[:notice]
    opportunity = Opportunity.last
    assert_equal "Backstage crew needed", opportunity.title
    assert_equal users(:member), opportunity.creator
    assert_nil opportunity.submitter_name
    assert_not opportunity.approved
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
          roles_attributes: { "0" => { position: "Stage Manager", department_name: "Stage Management" } }
        }
      }
    end

    opportunity = Opportunity.last
    assert_nil opportunity.creator_id
    assert opportunity.external?
    assert_equal "Jane External", opportunity.submitter_name
    assert_equal "Brand New Society", opportunity.company&.name
    assert_equal [ "Stage Manager" ], opportunity.roles.map(&:position)
    refute opportunity.approved
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

  test "create re-renders for a logged-out submission that fails reCAPTCHA" do
    # With no token and "test" not skipped, the gem returns false without calling Google.
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

  test "opportunities filters by role department without duplicating a posting" do
    ids = [ departments(:stage_management), departments(:set) ].map(&:id)
    get :opportunities, params: { q: { roles_department_id_in: ids } }

    listed = assigns(:opportunities).to_a
    assert_equal 1, listed.count(opportunities(:internal_project_opportunity))
    assert_not_includes listed, opportunities(:external_project_opportunity)
  end

  test "the department filter offers only departments on listed opportunities" do
    opportunities(:unapproved_opportunity).roles.create!(position: "Puppeteer", department: Department.create!(name: "Puppetry"))
    Department.create!(name: "Pyrotechnics")

    get :opportunities

    offered = css_select("select[name='q[roles_department_id_eq]'] option").map(&:text)
    assert_includes offered, "Lighting"
    assert_not_includes offered, "Puppetry"
    assert_not_includes offered, "Pyrotechnics"
  end

  test "opportunities filters by compensation type" do
    get :opportunities, params: { q: { compensation_type_eq: Opportunity.compensation_types[:paid] } }

    assert_includes assigns(:opportunities), opportunities(:external_project_opportunity)
    assert_not_includes assigns(:opportunities), opportunities(:internal_project_opportunity)
  end

  test "opportunities ignores a filter on a column the form does not offer" do
    get :opportunities, params: { q: { contact_email_start: "zzz" } }

    assert_response :success
    assert_includes assigns(:opportunities), opportunities(:external_project_opportunity)
  end

  test "opportunities does not error on a filter through the creator" do
    get :opportunities, params: { q: { creator_first_name_eq: "a" } }

    assert_response :success
  end

  test "opportunities responds to a turbo_stream request (live search)" do
    get :opportunities, params: { q: { company_slug_eq: companies(:gutter_theatre).slug } }, format: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/<turbo-stream[^>]*target="index-results"/, response.body)
    assert_includes assigns(:opportunities), opportunities(:external_project_opportunity)
    assert_not_includes assigns(:opportunities), opportunities(:internal_project_opportunity)
  end

  # A Turbo form redirect (after #create) follows with a turbo_stream Accept but no q, and a
  # fragment would do nothing on the form page (no #index-results), so it must get full HTML.
  test "opportunities serves a full HTML page for a paramless turbo_stream request" do
    get :opportunities, format: :turbo_stream

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_no_match(/<turbo-stream/, response.body)
    assert_match(/<h1[^>]*>\s*Opportunities/, response.body)
  end
end
