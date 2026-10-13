require "test_helper"

# A public submission cannot add a department; the reviewer picks or adds one on the admin form.
class OpportunityDepartmentReviewTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def submit_puppet_crew(**overrides)
    post get_involved_opportunities_path, params: { opportunity: {
      title: "Puppet crew", description: "Puppets.", expiry_date: 2.weeks.from_now.to_date,
      submitter_name: "Jane External", submitter_email: "jane.external@example.com",
      roles_attributes: { "0" => { position: "Puppeteer", department_name: "Puppetry" },
                          "1" => { position: "LX op", department_name: "lighting" } }
    }.merge(overrides) }
  end

  test "a logged-out submission's new department waits as a suggestion only reviewers see" do
    assert_no_difference("Department.count") { submit_puppet_crew }
    opportunity = Opportunity.find_by!(title: "Puppet crew")
    puppeteer = opportunity.roles.find_by!(position: "Puppeteer")
    lx_op = opportunity.roles.find_by!(position: "LX op")
    assert_nil puppeteer.department
    assert_equal "Puppetry", puppeteer.suggested_department
    assert_predicate puppeteer.note, :blank?
    assert_equal departments(:lighting), lx_op.department

    sign_in users(:admin)
    get admin_opportunity_path(opportunity)
    assert_select "li", text: /Puppeteer.*Suggested department: Puppetry/
    get edit_admin_opportunity_path(opportunity)
    assert_select "p", text: /Suggested department: Puppetry\./

    # Approved untouched, the public listing must not show the suggestion.
    put approve_admin_opportunity_path(opportunity)
    sign_out users(:admin)
    get get_involved_opportunities_path
    assert_select "li", text: /Puppeteer/
    assert_no_match(/Puppetry/, response.body)

    sign_in users(:admin)
    assert_difference("Department.count", 1) do
      patch admin_opportunity_path(opportunity), params: { opportunity: { roles_attributes: {
        "0" => { id: puppeteer.id, position: "Puppeteer", department_name: "Puppetry" },
        "1" => { id: lx_op.id, position: "LX op", department_name: "Set" }
      } } }
    end
    assert_redirected_to admin_opportunity_path(opportunity)
    assert_equal "Puppetry", puppeteer.reload.department.name
    assert_nil puppeteer.suggested_department
    assert_equal departments(:set), lx_op.reload.department

    get admin_opportunity_path(opportunity)
    assert_no_match(/Suggested department/, response.body)
  end

  test "a refused public submission does not show its typed department as a suggestion" do
    assert_no_difference("Opportunity.count") { submit_puppet_crew(submitter_email: "") }

    assert_no_match(/Suggested department/, response.body)
  end
end
