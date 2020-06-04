class ApplicationController < ActionController::Base
  protect_from_forgery
  before_action :set_paper_trail_whodunnit

  before_action :set_globals
  before_action :prepare_for_mobile

  check_authorization unless: :devise_controller?

  rescue_from Exception, with: :report_500     unless Rails.env.development? || Rails.env.test?
  rescue_from StandardError, with: :report_500 unless Rails.env.development? || Rails.env.test?

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to static_path('access_denied'), notice: exception.message
  end

  unless Rails.env.development? || Rails.env.test?
    # Unreachable, but easy to check manually.
    # :nocov:
    rescue_from ActiveRecord::RecordNotFound do |exception|
      flash[:notice] = exception.message
      raise(ActionController::RoutingError, 'Not Found')
    end
    # :nocov:
  end

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

    # Prevent redirect loop if 500 rendering fails.
    if request.env['PATH_INFO'] == static_path('500')
      Rails.logger.error 'Could not render the 500 page:'
      Rails.logger.error exception

      return render inline: 'Sorry. Something has gone very wrong. We will try to fix this asap.'
    end

    Rails.logger.warn 'Caught error and redirected to 500'
    Rails.logger.error exception
    Rails.logger.error exception.backtrace

    flash[:error] = exception.message.gsub Rails.root.to_s, ''

    redirect_to static_path('500', params[:format])
  end

  private

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
