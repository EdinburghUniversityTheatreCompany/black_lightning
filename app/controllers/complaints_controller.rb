# Only has a form.
class ComplaintsController < ApplicationController
  include GenericController

  load_and_authorize_resource

  def create
    @complaint.resolved = false

    super
  end

  private

  def create_redirect_url
    "/"
  end

  def permitted_params
    %i[subject description]
  end

  def on_create_success
    helpers.append_to_flash(:success, "Your Complaint or Suggestion has been successfully submitted. Thank you.")
  end

  def new_title
    "Submit Complaint or Suggestion"
  end
end
