require "test_helper"

class Admin::ProposalsHelperTest < ActionView::TestCase
  include LabelHelper

  setup do
    @call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.current.advance(days: 5), question_count: 3)
    @proposal = FactoryBot.create(:proposal, :with_team_members, call: @call)
  end

  def labels(html) = Nokogiri::HTML.fragment(html).css("span").map { |s| [ s.text, s["class"][/bg-(\w+)/, 1] ] }

  [
    [ :successful, false, true, [ [ "Successful", "success" ], [ "Has Debtors", "danger" ] ] ],
    [ :rejected, true, false, [ [ "Rejected", "danger" ], [ "Late", "danger" ] ] ],
    [ :awaiting_approval, true, true, [ [ "Awaiting Approval", "info" ], [ "Late", "danger" ], [ "Has Debtors", "danger" ] ] ],
    [ :approved, false, false, [ [ "Approved", "success" ] ] ],
    [ :unsuccessful, false, false, [ [ "Unsuccessful", "danger" ] ] ]
  ].each do |status, late, debtors, expected|
    test "labels for a #{status} proposal#{' that was late' if late}#{' with debtors' if debtors}" do
      @proposal.status = status
      @proposal.late = late
      FactoryBot.create(:staffing_debt, user: @proposal.users.first, due_by: @call.editing_deadline.advance(days: -1)) if debtors

      assert_equal expected, labels(proposal_labels(@proposal, false))
    end
  end

  test "pull_right wraps the labels in a float-right div" do
    assert_match(/\A<div class="float-right">.*<\/div>\z/m, proposal_labels(@proposal, true))
  end
end
