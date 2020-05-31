require 'test_helper'
require 'rake'

# Tests the debt rake tasks.
class MigrationsTaskTest < ActiveSupport::TestCase
  test 'should fix calls where editing deadline is nil' do
    correct_call = FactoryBot.create(:proposal_call)
    editing_deadline = correct_call.editing_deadline

    assert_not_equal editing_deadline, correct_call.submission_deadline

    incorrect_call = FactoryBot.build(:proposal_call, editing_deadline: nil)
    incorrect_call.save(validate: false)

    assert_equal 1, MigrationsTaskLogic.fix_editing_deadline

    correct_call = Admin::Proposals::Call.find(correct_call.id)
    incorrect_call = Admin::Proposals::Call.find(incorrect_call.id)

    assert_equal editing_deadline, correct_call.editing_deadline

    assert_equal incorrect_call.submission_deadline, incorrect_call.editing_deadline
  end
end
