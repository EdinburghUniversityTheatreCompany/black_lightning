##
# Controller for Admin::Proposals::CallQuestionTemplate. More details can be found there.
##

class Admin::Proposals::CallQuestionTemplatesController < AdminController
  include GenericController

  load_and_authorize_resource

  private

  def resource_class
    Admin::Proposals::CallQuestionTemplate
  end

  def includes_args
    [ :questions ]
  end

  # :admin_proposals_call_question_template
  def permitted_params
    [ :name, { questions_attributes: %I[question_text response_type _destroy id] } ]
  end

  def edit_title
    "Edit #{@call_question_template.name} Template"
  end

  def new_title
    "New Proposal Call Question Template"
  end

  def json_enabled_for_index?
    true
  end
end
