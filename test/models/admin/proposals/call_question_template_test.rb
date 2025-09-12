# == Schema Information
#
# Table name: admin_proposals_call_question_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class CallQuestionTemplateTest < ActionView::TestCase
  test "as_json" do
    @call_question_template = admin_proposals_call_question_templates(:lunchtime)

    FactoryBot.create_list(:question, 5, questionable: @call_question_template)

    assert 5, @call_question_template.questions.count

    json = @call_question_template.reload.as_json

    assert json.is_a? Hash
    assert json.key? "questions"
  end
end
