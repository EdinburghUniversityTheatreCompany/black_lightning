# == Schema Information
#
# Table name: admin_proposals_calls
#
# *id*::         <tt>integer, not null, primary key</tt>
# *deadline*::   <tt>datetime</tt>
# *name*::       <tt>string(255)</tt>
# *open*::       <tt>boolean</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *archived*::   <tt>boolean</tt>
#--
# == Schema Information End
#++

require 'test_helper'

class Admin::Proposals::ProposalTest < ActiveSupport::TestCase
  test "archive" do
    call = FactoryGirl.create(:proposal_call, open: true)
    call.archive

    assert(call.open == false)
    assert(call.archived)
  end
end
