##
# Controller for Admin::Questionnaires::QuestionnaireTemplate
##
class Admin::Questionnaires::QuestionnaireTemplatesController < AdminController
  include GenericController

  load_and_authorize_resource

  ##
  # GET /admin/questionnaires/questionnaire_templates/1
  #
  # GET /admin/questionnaires/questionnaire_templates/1.json
  ##
  def show
    @title = "#{@questionnaire_template.name} Questionnaire Template"
    super
  end

  private

  def resource_class
    Admin::Questionnaires::QuestionnaireTemplate
  end

  def permitted_params
    [ :name, questions_attributes: [ :id, :_destroy, :question_text, :response_type ], notify_emails_attributes: [ :id, :_destroy, :email ] ]
  end

  def edit_title
    "Edit #{@questionnaire_template.name}"
  end

  def json_enabled_for_index?
    true
  end
end
