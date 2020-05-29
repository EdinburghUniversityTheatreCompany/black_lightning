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

class Admin::Proposals::CallTest < ActiveSupport::TestCase
  test 'open' do
    old_call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.now.advance(days: -1), editing_deadline: DateTime.now.advance(days: 1))
    new_call = FactoryBot.create(:proposal_call, submission_deadline: DateTime.now.advance(days: 1))

    assert new_call.open?
    assert_not old_call.open?

    assert_includes Admin::Proposals::Call.open, new_call
    assert_not_includes Admin::Proposals::Call.open, old_call
  end

  test 'archive' do
    call = FactoryBot.create(:proposal_call, archived: false, editing_deadline: DateTime.now.advance(days: -1))

    assert call.archive

    assert call.archived
  end

  test 'instantiates answers on proposals after save' do
    call = FactoryBot.create(:proposal_call)

    call.proposals.each do |proposal|
      assert_equal call.questions.count, proposal.questions.count
      assert_equal call.questions.count, proposal.answers.count
    end
  end

  test 'cannot archive before the submission deadline has been reached' do
    call = FactoryBot.create(:proposal_call, archived: false, editing_deadline: DateTime.now.advance(days: 1))

    assert_not call.archive

    assert_not call.archived
  end

  test 'cannot destroy call with proposals attached' do
    call = FactoryBot.create(:proposal_call, proposal_count: 1)

    assert_no_difference('Admin::Proposals::Call.count') do
      assert_not call.destroy
    end

    assert_match 'You cannot destroy the call because there are proposals attached to it.', call.errors.full_messages.join('')

    call.proposals.clear

    assert_difference 'Admin::Proposals::Call.count', -1 do
      assert call.destroy
    end
  end
end
