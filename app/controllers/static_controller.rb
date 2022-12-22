class StaticController < ApplicationController
  skip_authorization_check
  
  # This is a catch-all for the pages that do not have explicitly defined routes.
  def show
    begin
      render "static/#{params[:page]}"
    rescue
      Rails.logger.error "Could not find the page at #{request.fullpath}"

      raise(ActionController::RoutingError.new('This page could not be found.'))
    end
  end

  def home
    @events = Event.includes(image_attachment: :blob).current.reorder('start_date ASC')
    @news = News.accessible_by(current_ability).includes(:author).order('publish_date DESC').current.first(4)

    @carousel_items = CarouselItem.where(carousel_name: 'Home').active_and_ordered.includes(image_attachment: :blob)
  end

  def contact_form_send
    sender_email = params[:contact][:email]
    name = params[:contact][:name]
    recipient_email = params[:contact][:recipient]
    subject = params[:contact][:subject]
    message = params[:contact][:message]

    ContactFormMailer.contact_form_mail(sender_email, recipient_email, name, subject, message).deliver_later

    success_message = "Email with subject \"#{subject}\" has been successfully sent to #{recipient_email}"
    helpers.append_to_flash(:success, success_message)

    respond_to do |format|
      format.html { redirect_to(static_url('contact')) }
      format.json { render json: success_message }
    end
  end
end
