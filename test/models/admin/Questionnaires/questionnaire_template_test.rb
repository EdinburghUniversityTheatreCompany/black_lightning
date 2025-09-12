# == Schema Information
#
# Table name: admin_questionnaires_questionnaire_templates
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
require "test_helper"

class Admin::Questionnaires::QuestionnaireTemplateTest < ActiveSupport::TestCase
  test "as_json" do
    questionnaire_template = admin_questionnaires_questionnaire_templates(:one)

    json = questionnaire_template.as_json

    assert json.is_a? Hash
    assert json.key?("name")
    assert json.key?("questions")
  end
end
