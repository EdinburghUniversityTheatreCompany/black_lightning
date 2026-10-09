require "test_helper"

# A public submission cannot add a department; the reviewer picks or adds one on the admin form.
class OpportunityDepartmentReviewTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "a logged-out submission's new department waits in the note until the reviewer adds it" do
    assert_no_difference("Department.count") do
      post get_involved_opportunities_path, params: { opportunity: {
        title: "Puppet crew", description: "Puppets.", expiry_date: 2.weeks.from_now.to_date,
        submitter_name: "Jane External", submitter_email: "jane.external@example.com",
        roles_attributes: { "0" => { position: "Puppeteer", department_name: "Puppetry" },
                            "1" => { position: "LX op", department_name: "lighting" } }
      } }
    end
    opportunity = Opportunity.find_by!(title: "Puppet crew")
    puppeteer = opportunity.roles.find_by!(position: "Puppeteer")
    lx_op = opportunity.roles.find_by!(position: "LX op")
    assert_nil puppeteer.department
    assert_equal "Department: Puppetry", puppeteer.note
    assert_equal departments(:lighting), lx_op.department

    sign_in users(:admin)
    get admin_opportunity_path(opportunity)
    assert_select "li", text: /Puppeteer.*Department: Puppetry/

    assert_difference("Department.count", 1) do
      patch admin_opportunity_path(opportunity), params: { opportunity: { roles_attributes: {
        "0" => { id: puppeteer.id, position: "Puppeteer", department_name: "Puppetry", note: "" },
        "1" => { id: lx_op.id, position: "LX op", department_name: "Set" }
      } } }
    end
    assert_redirected_to admin_opportunity_path(opportunity)
    assert_equal "Puppetry", puppeteer.reload.department.name
    assert_predicate puppeteer.note, :blank?
    assert_equal departments(:set), lx_op.reload.department
  end
end
