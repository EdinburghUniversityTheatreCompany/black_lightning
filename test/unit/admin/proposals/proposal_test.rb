# == Schema Information
#
# Table name: admin_proposals_proposals
#
#  id             :integer          not null, primary key
#  call_id        :integer
#  show_title     :string(255)
#  publicity_text :text
#  proposal_text  :text
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  late           :boolean
#  approved       :boolean
#  successful     :boolean
#

require 'test_helper'

class Admin::Proposals::ProposalTest < ActiveSupport::TestCase
  test "convert to show" do
    @admin_proposals_proposal = ::Admin::Proposals::Proposal.find(1)
    job = @admin_proposals_proposal.convert_to_show()
    job.invoke_job

    assert ::Show.find_by_name('Test Proposal')
  end
end
