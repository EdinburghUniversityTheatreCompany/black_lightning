# Only has a form.
class ComplaintsController < ApplicationController
  include GenericController

  load_and_authorize_resource

  def create
    unless verify_recaptcha(action: 'submit_complaint', score: 0.5)
      render 'new'

      return
    end

    @complaint.resolved = false
    
    super
  end

  private

  def create_redirect_url
    return '/'
  end

  def permitted_params
    [:subject, :description]
  end

  def on_create_success
    helpers.append_to_flash(:success, 'Your Complaint or Suggestion has been successfully submitted. Thank you.')
  end
end
