# == Schema Information
#
# Table name: admin_proposals_proposals
#
# *id*::             <tt>integer, not null, primary key</tt>
# *call_id*::        <tt>integer</tt>
# *show_title*::     <tt>string(255)</tt>
# *publicity_text*:: <tt>text</tt>
# *proposal_text*::  <tt>text</tt>
# *created_at*::     <tt>datetime, not null</tt>
# *updated_at*::     <tt>datetime, not null</tt>
# *late*::           <tt>boolean</tt>
# *approved*::       <tt>boolean</tt>
# *successful*::     <tt>boolean</tt>
#--
# == Schema Information End
#++

require 'test_helper'

class Admin::Proposals::ProposalTest < ActiveSupport::TestCase
  test "convert to show" do
    call = FactoryGirl.create(:proposal_call)

    proposal = FactoryGirl.create(:proposal, call: call, approved: true)

    proposal.convert_to_show()

    assert ::Show.find_by_name(proposal.show_title)
  end
end
