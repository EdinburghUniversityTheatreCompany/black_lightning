# Only has a form.
class ComplaintsController < ApplicationController
  include GenericController

  load_and_authorize_resource

  def create
    # I do not know how to deliberately fail the captcha, as the entire check is disabled in testing.
    # :nocov:
    unless verify_recaptcha(action: 'submit_complaint', score: 1)
      render 'new'

      return
    end
    # :nocov:

    @complaint.resolved = false

    super

    ComplaintsMailer.new_complaint(@complaint).deliver_later unless @complaint.new_record?
  end

  private

  def create_redirect_url
    return '/'
  end

  def permitted_params
    %i[subject description]
  end

  def on_create_success
    helpers.append_to_flash(:success, 'Your Complaint or Suggestion has been successfully submitted. Thank you.')
  end

  def new_title
    'Submit Complaint or Suggestion'
  end
end
