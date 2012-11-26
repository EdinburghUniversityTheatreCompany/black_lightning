require 'test_helper'

class Admin::Proposals::ProposalTest < ActiveSupport::TestCase
  test "convert to show" do
    @admin_proposals_proposal = ::Admin::Proposals::Proposal.find(1)
    job = @admin_proposals_proposal.convert_to_show()
    job.invoke_job

    assert ::Show.find_by_name('Test Proposal')
  end
end
