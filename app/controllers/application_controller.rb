class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  before_action :set_paper_trail_whodunnit

  before_action :set_globals
  before_action :prepare_for_mobile

  check_authorization unless: :devise_controller?

  rescue_from Exception, with: :report_500     unless Rails.env.development? || Rails.env.test?
  rescue_from StandardError, with: :report_500 unless Rails.env.development? || Rails.env.test?

  rescue_from CanCan::AccessDenied, with: :report_access_denied

  rescue_from ActiveRecord::RecordNotFound, with: :report_404# unless Rails.env.development? || Rails.env.test?
  rescue_from ActionController::RoutingError, with: :report_404 
  
  def set_globals
    @base_url = request.protocol + request.host_with_port
    # Create the @meta hash
    @meta = {
      description: 'The Bedlam Theatre is a unique, entirely student run theatre in the heart of Edinburgh.',

      # facebook opengraph data:
      'og:url' => @base_url + request.fullpath,
      'og:image' => @base_url + helpers.image_path('BedlamLogoBW.png'),
      'og:title' => @title ? "#{@title} - Bedlam Theatre" : 'Bedlam Theatre',

      'viewport' => 'initial-scale = 1.0,maximum-scale = 1.0'
    }

    @support_email = 'it@bedlamtheatre.co.uk'
  end

  def report_500(exception)
    Honeybadger.notify(exception)

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
    @meta['ROBOTS'] = 'NOINDEX, NOFOLLOW'

    helpers.append_to_flash(:error, exception.message.gsub(Rails.root.to_s, ''))

    @error_type = exception.class

    respond_to do |type|
      type.html { render template: template, status: status_code, layout: helpers.current_environment(request.fullpath) }
      type.json { render json: { error: flash[:error] }, status: status_code }
      type.all  { render body: nil, status: status_code }
    end
  end

  # Believed to match about 98% of mobile browsers. https://gist.github.com/1503252
  MOBILE_REGEX = /Mobile|iP(hone|od)|Android|BlackBerry|IEMobile|Kindle|NetFront|Silk-Accelerated|(hpw|web)OS|Fennec|Minimo|Opera M(obi|ini)|Blazer|Dolfin|Dolphin|Skyfire|Zune/

  ##
  # Mobile device detection
  ##
  def mobile_device?
    if session[:mobile_param]
      session[:mobile_param] == 'true'
    else
      request.user_agent =~ MOBILE_REGEX
    end
  end
  helper_method :mobile_device?

  def prepare_for_mobile
    session[:mobile_param] = params[:mobile] if params[:mobile]
  end
end
