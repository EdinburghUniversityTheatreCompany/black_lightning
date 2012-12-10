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
    @admin_proposals_call = ::Admin::Proposals::Call.find(1)
    @admin_proposals_call.archive
    @admin_proposals_call = ::Admin::Proposals::Call.find(1)

    assert(@admin_proposals_call.open == false)
    assert(@admin_proposals_call.archived)
  end
end
