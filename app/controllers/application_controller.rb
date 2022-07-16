class ApplicationController < ActionController::Base
  include SubpageHelper

  protect_from_forgery with: :exception
  before_action :set_paper_trail_whodunnit

  before_action :set_globals
  before_action :set_navbar

  check_authorization unless: :devise_controller?

  rescue_from Exception, with: :report_500     unless Rails.env.development? || Rails.env.test?
  rescue_from StandardError, with: :report_500 unless Rails.env.development? || Rails.env.test?

  rescue_from CanCan::AccessDenied, with: :report_access_denied

  rescue_from ActiveRecord::RecordNotFound, with: :report_404# unless Rails.env.development? || Rails.env.test?
  rescue_from ActionController::RoutingError, with: :report_404 

  def set_globals
    @base_url = request.protocol + request.host_with_port
    @current_path = request.path
  
    # Create the @meta hash
    @meta = {
      description: 'The Bedlam Theatre is a unique, entirely student run theatre in the heart of Edinburgh.',

      # facebook opengraph data:
      'og:url' => @base_url + request.fullpath,
      'og:image' => @base_url + helpers.image_path('BedlamLogoBW.png'),
      'og:title' => @title ? "#{@title} - Bedlam Theatre" : 'Bedlam Theatre',

      'viewport' => 'width=device-width, initial-scale=1'
    }

    @support_email = 'it@bedlamtheatre.co.uk'
  end

  def set_navbar
    @navbar_items = [
      { title: 'Events',        path: events_path },
      { title: 'About',         children: get_navbar_children('about') },
      { title: 'Get Involved',  children: get_navbar_children('get_involved') },
      { title: 'Archives',      children: get_navbar_children('archives') },
      { title: 'Contact',       path: static_path('contact') },
      { title: 'Accessibility', path: static_path('accessibility') }
    ]

    # Display the login link if the user is not signed in yet, otherwise display a link to the admin site and a link to log out.
    if user_signed_in?
      @navbar_items << { title: 'Members', path: admin_path }
      @navbar_items << { title: 'Log Out', path: destroy_user_session_path, method: :delete, item_class: 'border border-white rounded-3' }
    else
      # Use admin_path rather than user_session_path so someone is automatically redirected to the admin site after loggingg in.
      @navbar_items << { title: 'Log In', path: admin_path, item_class: 'border border-white rounded-3' }
    end
  end

  def report_500(exception)
    Honeybadger.notify(exception, context: {
      user_email: current_user&.email,
      user_name: current_user&.name_or_email
    })

    Rails.logger.warn 'Caught error and redirected to 500'
    Rails.logger.error exception
    Rails.logger.error exception.backtrace

    render_error_page(exception, 'errors/500', 500)
  end

  def report_access_denied(exception)
    render_error_page(exception, 'errors/access_denied', 403)
  end

  def report_404(exception)
    render_error_page(exception, 'errors/404', 404)
  end

  private

  def render_error_page(exception, template, status_code)
    @meta = {} if @meta.nil?
    @meta['ROBOTS'] = 'NOINDEX, NOFOLLOW'

    helpers.append_to_flash(:error, exception.message.gsub(Rails.root.to_s, ''))

    @error_type = exception.class

    respond_to do |type|
      type.html { render template: template, status: status_code, layout: helpers.current_environment(request.fullpath) }
      type.json { render json: { error: flash[:error] }, status: status_code }
      type.all  { render body: nil, status: status_code }
    end
  end
end
