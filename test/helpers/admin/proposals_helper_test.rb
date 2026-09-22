require "test_helper"

BASE_BADGE_CLASSES = "inline-flex items-center rounded px-2 py-0.5 text-xs font-medium"

class Admin::ProposalsHelperTest < ActionView::TestCase
  class ProposalLabelsTest < ActionView::TestCase
    include LabelHelper

    setup do
      @call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.current.advance(days: 5), question_count: 3)
      @proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)
    end

    test "labels for successful proposal with debtors" do
      @proposal.status = :successful
      _debt = FactoryBot.create(:staffing_debt, user: @proposal.users.first, due_by: @call.editing_deadline.advance(days: -1))
      expected_labels = "<span class=\"#{BASE_BADGE_CLASSES} bg-success/15 text-success\">Successful</span>\n<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Has Debtors</span>"

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for rejected proposal that was late with pull right" do
      @proposal.late = true
      @proposal.status = :rejected

      expected_labels = "<div class=\"float-right\"><span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Rejected</span>\n<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Late</span></div>"

      assert_equal expected_labels, proposal_labels(@proposal, true)
    end

    test "labels for proposal awaiting approval with debtors that was late" do
      @proposal.status = :awaiting_approval
      @proposal.late = true
      _debt = FactoryBot.create(:staffing_debt, user: @proposal.users.first, due_by: @call.editing_deadline.advance(days: -1))

      expected_labels = "<span class=\"#{BASE_BADGE_CLASSES} bg-info/15 text-info\">Awaiting Approval</span>\n<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Late</span>\n<span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Has Debtors</span>"

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for approved proposal" do
      @proposal.status = :approved

      expected_labels = "<span class=\"#{BASE_BADGE_CLASSES} bg-success/15 text-success\">Approved</span>"

      assert_equal expected_labels, proposal_labels(@proposal, false)
    end

    test "labels for unsuccessful proposal with pull right" do
      @proposal.status = :unsuccessful

      expected_labels = "<div class=\"float-right\"><span class=\"#{BASE_BADGE_CLASSES} bg-danger/15 text-danger\">Unsuccessful</span></div>"

      assert_equal expected_labels, proposal_labels(@proposal, true)
    end
  end
end
