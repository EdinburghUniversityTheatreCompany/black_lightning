require "test_helper"

class OpportunityCardComponentTest < ViewComponent::TestCase
  test "builds the heading from company, project and author when there is no title" do
    render_inline(OpportunityCardComponent.new(opportunity: opportunities(:internal_project_opportunity)))

    assert_text "Edinburgh University Theatre Company: 'Eurydice' by Sarah Ruhl"
  end

  test "prefers an explicit title for the heading" do
    render_inline(OpportunityCardComponent.new(opportunity: opportunities(:external_project_opportunity)))

    assert_text "Gutter Theatre crew call"
  end

  test "shows an EUTC badge for internal companies only" do
    render_inline(OpportunityCardComponent.new(opportunity: opportunities(:internal_project_opportunity)))
    assert_text "EUTC"

    render_inline(OpportunityCardComponent.new(opportunity: opportunities(:external_project_opportunity)))
    assert_no_text "EUTC"
  end

  test "lists the roles with their notes" do
    render_inline(OpportunityCardComponent.new(opportunity: opportunities(:internal_project_opportunity)))

    assert_text "Stage Manager"
    assert_text "Set Manager"
    assert_text "Sound Technician"
    assert_text "Build weekends only"
  end

  test "shows the contact link in detailed mode when visibility allows" do
    render_inline(OpportunityCardComponent.new(opportunity: opportunities(:external_project_opportunity), detailed: true))

    assert_selector "a[href='mailto:jane@example.com']"
  end

  test "hides the contact when visibility is no_one even with backend access" do
    render_inline(OpportunityCardComponent.new(opportunity: opportunities(:internal_project_opportunity), detailed: true, backend_access: true))

    assert_no_selector "a[href^='mailto:']"
  end

  test "members-only contact shows only with backend access" do
    opp = Opportunity.new(title: "Members only role", description: "d", expiry_date: 2.weeks.from_now,
                          email_visibility: :members_only, contact_email: "secret@example.com",
                          submitter_name: "S", submitter_email: "s@example.com")

    render_inline(OpportunityCardComponent.new(opportunity: opp, detailed: true, backend_access: true))
    assert_selector "a[href='mailto:secret@example.com']"

    render_inline(OpportunityCardComponent.new(opportunity: opp, detailed: true, backend_access: false))
    assert_no_selector "a[href='mailto:secret@example.com']"
  end

  test "suppresses compensation and experience badges at their default values" do
    opp = Opportunity.new(title: "No-signal posting", description: "d", expiry_date: 2.weeks.from_now,
                          compensation_type: :tbc, experience_level: :any,
                          submitter_name: "S", submitter_email: "s@example.com")

    render_inline(OpportunityCardComponent.new(opportunity: opp, detailed: true))
    assert_no_text "Tbc"
    assert_no_text "Any"
  end

  test "renders the role's department name as a badge" do
    opp = Opportunity.new(title: "FoH call", description: "d", expiry_date: 2.weeks.from_now,
                          submitter_name: "S", submitter_email: "s@example.com",
                          roles: [ OpportunityRole.new(position: "FoH Manager", department: departments(:lighting)) ])

    render_inline(OpportunityCardComponent.new(opportunity: opp))
    assert_text "Lighting"
  end

  test "compact mode links the heading and omits the description" do
    render_inline(OpportunityCardComponent.new(opportunity: opportunities(:external_project_opportunity), heading_url: "/get_involved/opportunities"))

    assert_selector "a[href='/get_involved/opportunities']", text: "Gutter Theatre crew call"
    assert_no_text "External company looking for technicians."
  end
end
