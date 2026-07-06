# == Schema Information
#
# Table name: opportunities
#
# *id*::          <tt>integer, not null, primary key</tt>
# *title*::       <tt>string(255)</tt>
# *description*:: <tt>text(65535)</tt>
# *show_email*::  <tt>boolean</tt>
# *approved*::    <tt>boolean</tt>
# *creator_id*::  <tt>integer</tt>
# *approver_id*:: <tt>integer</tt>
# *expiry_date*:: <tt>date</tt>
# *created_at*::  <tt>datetime, not null</tt>
# *updated_at*::  <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::OpportunityTest < ActionView::TestCase
  test "active?" do
    opportunity = FactoryBot.create(:opportunity, approved: false, expiry_date: Date.current.advance(days: -1))

    assert_not opportunity.active?
    opportunity.approved = true

    assert_not opportunity.active?
    opportunity.expiry_date = Date.current.advance(days: 1)

    assert opportunity.active?
    opportunity.approved = false

    assert_not opportunity.active?
  end

  test "email_visibility defaults to no_one" do
    opp = Opportunity.new
    assert opp.no_one?
  end

  test "email_visibility enum has correct values" do
    assert_equal 0, Opportunity.email_visibilities[:no_one]
    assert_equal 1, Opportunity.email_visibilities[:members_only]
    assert_equal 2, Opportunity.email_visibilities[:everyone]
  end

  test "contact_email is optional" do
    opp = opportunities(:active_opportunity)
    opp.contact_email = nil
    assert opp.valid?
  end

  test "contact_email validates format when present" do
    opp = opportunities(:active_opportunity)
    opp.contact_email = "not-an-email"
    assert_not opp.valid?
    assert_includes opp.errors[:contact_email], "is invalid"
  end

  test "should return the correct css class" do
    opportunity = FactoryBot.create :opportunity, expiry_date: Date.current.advance(days: -1)

    assert_equal "", opportunity.css_class

    opportunity.expiry_date = Date.current.advance(days: 1)
    opportunity.approved = false

    assert_equal "table-danger".html_safe, opportunity.css_class

    opportunity.approved = true

    assert_equal "table-success".html_safe, opportunity.css_class
  end

  test "is valid with a creator and no submitter details" do
    assert opportunities(:active_opportunity).valid?
  end

  test "is valid as an external submission with submitter name and email" do
    opp = opportunities(:external_project_opportunity)
    assert_nil opp.creator_id
    assert opp.valid?
  end

  test "is invalid without a creator or submitter" do
    opp = Opportunity.new(title: "T", description: "D", expiry_date: 1.week.from_now)
    assert_not opp.valid?
    assert_includes opp.errors[:base], "must have a creator or a submitter name and email"
  end

  test "is valid without a title when a company and project provide a heading" do
    opp = opportunities(:internal_project_opportunity)
    assert_nil opp.title
    assert opp.valid?, opp.errors.full_messages.to_sentence
  end

  test "is invalid with neither a title nor a company/project heading" do
    opp = Opportunity.new(description: "D", expiry_date: 1.week.from_now, creator: users(:admin))
    assert_not opp.valid?
    assert_includes opp.errors[:base], "must have a title, or a company and project"
  end

  test "external? is true only when there is no creator" do
    assert opportunities(:external_project_opportunity).external?
    assert_not opportunities(:internal_project_opportunity).external?
  end

  test "on_behalf_of? is true only when a creator recorded an external submitter" do
    assert_not opportunities(:internal_project_opportunity).on_behalf_of?, "creator-only posting is not on behalf"
    assert_not opportunities(:external_project_opportunity).on_behalf_of?, "creator-less posting is external, not on behalf"

    on_behalf = Opportunity.new(title: "T", description: "D", expiry_date: 1.week.from_now,
                                creator_id: 1, submitter_name: "Jane Director",
                                submitter_email: "jane@example.com")
    assert on_behalf.on_behalf_of?
  end

  test "display_title falls back to company and project" do
    opp = opportunities(:internal_project_opportunity)
    assert_nil opp.title
    assert_equal "Edinburgh University Theatre Company: Eurydice", opp.display_title
  end

  test "display_title prefers an explicit title" do
    assert_equal "Gutter Theatre crew call", opportunities(:external_project_opportunity).display_title
  end

  test "company_name falls back to the associated company" do
    assert_equal companies(:gutter_theatre).name, opportunities(:external_project_opportunity).company_name
  end

  test "company_name resolves to an existing company (case-insensitive)" do
    opp = Opportunity.new(title: "T", description: "D", expiry_date: 1.week.from_now, creator_id: 1,
                          company_name: companies(:gutter_theatre).name.upcase)
    opp.validate
    assert_equal companies(:gutter_theatre), opp.company
  end

  test "company_name creates a new, unreviewed company when it does not match" do
    opp = Opportunity.new(title: "T", description: "D", expiry_date: 1.week.from_now, creator_id: 1,
                          company_name: "A Brand New Society")
    assert_difference("Company.count", 1) { opp.save! }
    assert_equal "A Brand New Society", opp.company.name
    assert_not opp.company.reviewed, "newly created companies should be unreviewed"
  end

  test "blank company_name clears the company" do
    opp = opportunities(:external_project_opportunity)
    opp.company_name = ""
    opp.validate
    assert_nil opp.company
  end

  test "resolved_contact_email prefers contact_email then submitter then creator" do
    opp = opportunities(:external_project_opportunity)
    assert_equal "jane@example.com", opp.resolved_contact_email

    opp.contact_email = "explicit@example.com"
    assert_equal "explicit@example.com", opp.resolved_contact_email
  end

  test "notification_email targets the submitter, ignoring the public contact_email" do
    # External submission: notify the submitter, not the (possibly third-party) contact_email.
    external = opportunities(:external_project_opportunity)
    external.contact_email = "someone-else@example.com"
    assert_equal "jane@example.com", external.notification_email

    # Member submission: notify the creator's account.
    internal = opportunities(:internal_project_opportunity)
    assert_equal internal.creator.email, internal.notification_email
  end

  test "notification_email and notification_name prefer the external submitter for on-behalf postings" do
    # When a manager posts on an external person's behalf, the creator records who entered it,
    # but approval/rejection decisions should still reach the external person.
    on_behalf = Opportunity.new(title: "T", description: "D", expiry_date: 1.week.from_now,
                                creator: users(:admin), submitter_name: "Jane Director",
                                submitter_email: "jane@example.com")
    assert_equal "jane@example.com", on_behalf.notification_email
    assert_equal "Jane Director", on_behalf.notification_name
  end

  test "submitter_display_name prefers the external submitter over the account creator" do
    # A posting can carry both an account creator and an external submitter (e.g. a manager
    # attributes it to an account but records who actually submitted). The displayed contact name
    # must match resolved_contact_email, which prefers the submitter — otherwise the show page
    # pairs the creator's name with the submitter's email.
    opp = Opportunity.new(title: "T", description: "D", expiry_date: 1.week.from_now,
                          creator_id: 1, submitter_name: "Jane Director",
                          submitter_email: "jane@example.com")
    assert_equal "Jane Director", opp.submitter_display_name

    # With no external submitter, fall back to the account creator.
    member = opportunities(:internal_project_opportunity)
    assert_equal member.creator.name, member.submitter_display_name
  end

  test "submitter_email validates format when present" do
    opp = opportunities(:external_project_opportunity)
    opp.submitter_email = "nope"
    assert_not opp.valid?
    assert_includes opp.errors[:submitter_email], "is invalid"
  end

  test "destroying an opportunity destroys its unreviewed company when it has no other opportunities" do
    opp = Opportunity.create!(title: "T", description: "D", expiry_date: 1.week.from_now, creator_id: 1,
                              company_name: "Orphan Society", approved: false)
    company = opp.company
    assert_not company.reviewed

    assert_difference("Company.count", -1) { opp.destroy }
    assert_raises(ActiveRecord::RecordNotFound) { company.reload }
  end

  test "destroying an opportunity keeps its unreviewed company when it has other opportunities" do
    opp1 = Opportunity.create!(title: "T1", description: "D", expiry_date: 1.week.from_now, creator_id: 1,
                               company_name: "Shared Society", approved: false)
    opp2 = Opportunity.create!(title: "T2", description: "D", expiry_date: 1.week.from_now, creator_id: 1,
                               company_name: "Shared Society", approved: false)
    company = opp1.company

    assert_no_difference("Company.count") { opp1.destroy }
    assert company.reload.persisted?
  end

  test "destroying an opportunity keeps a reviewed company" do
    opp = Opportunity.create!(title: "T", description: "D", expiry_date: 1.week.from_now, creator_id: 1,
                              company_name: companies(:gutter_theatre).name, approved: false)
    assert companies(:gutter_theatre).reviewed

    assert_no_difference("Company.count") { opp.destroy }
  end

  test "active orders internal companies first" do
    active = Opportunity.active.to_a
    assert_includes active, opportunities(:internal_project_opportunity)
    internal_index = active.index(opportunities(:internal_project_opportunity))
    external_index = active.index(opportunities(:external_project_opportunity))
    assert internal_index < external_index, "internal company opportunities should sort before external ones"
  end
end
