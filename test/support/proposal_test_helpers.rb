# Shared by the proposal page and the calls index, which both render the Approve button.
module ProposalTestHelpers
  # A proposal awaiting approval after submissions close, with one team member in debt.
  def create_proposal_with_debtor(call)
    call.update_attribute(:submission_deadline, DateTime.current.advance(days: -1))
    proposal = FactoryBot.create(:proposal, :with_team_members, call: call, status: :awaiting_approval)
    FactoryBot.create(:maintenance_debt, user: proposal.users.first, due_by: Date.current.advance(days: -1))
    proposal
  end

  def assert_debtor_approval_question(proposal)
    assert_select "form[action=?][data-turbo-confirm=?]", approve_admin_proposals_proposal_path(proposal),
                  "#{proposal.show_title} has debtors on its team. Approve it anyway?"
  end
end
