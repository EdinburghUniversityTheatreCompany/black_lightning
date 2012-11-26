require 'test_helper'

class Admin::Proposals::ProposalTest < ActiveSupport::TestCase
  test "archive" do
    @admin_proposals_call = ::Admin::Proposals::Call.find(1)
    @admin_proposals_call.archive
    @admin_proposals_call = ::Admin::Proposals::Call.find(1)

    assert(@admin_proposals_call.open == false)
    assert(@admin_proposals_call.archived)
  end
end
