class ApplicationController < ActionController::Base
  # rescue_from DeviseLdapAuthenticatable::LdapException do |exception|
  #   render :text => exception, :status => 500
  # end
  protect_from_forgery except: :options
  before_action :set_paper_trail_whodunnit

  before_filter :set_globals
  before_filter :prepare_for_mobile

  rescue_from Exception, with: :report_500     unless Rails.env.development? || Rails.env.test?
  rescue_from StandardError, with: :report_500 unless Rails.env.development? || Rails.env.test?

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to static_path('access_denied'), notice: exception.message
  end

  unless Rails.env.development? || Rails.env.test?
    rescue_from ActiveRecord::RecordNotFound do |exception|
      flash[:notice] = exception.message
      fail ActionController::RoutingError.new('Not Found')
    end
  end

  def options
    headers['Access-Control-Allow-Origin'] = request.env['HTTP_ORIGIN']
    headers['Access-Control-Allow-Methods'] = 'POST, GET, DELETE, OPTIONS'
    headers['Access-Control-Max-Age'] = '1000'
    headers['Access-Control-Allow-Headers'] = '*,x-requested-with,X-CSRF-Token,Authorization'

    head :ok
  end

  def authorize_backend!
    authorize! :access, :backend
  end

  def set_globals
    @base_url = request.protocol + request.host_with_port
    # Create the @meta hash
    @meta = {}
    @support_email = 'it@bedlamtheatre.co.uk'
  end

  def report_500(ex)
    # Prevent redirect loop if 500 rendering fails.
    if request.env['PATH_INFO'] == static_path('500')
      Rails.logger.error 'Could not render the 500 page:'
      Rails.logger.error ex

      return render inline: 'Sorry. Something has gone very wrong. We will try to fix this asap.'
    end

    Rails.logger.warn  'Caught error and redirected to 500'
    Rails.logger.error ex
    Rails.logger.error ex.backtrace

    flash[:error] = ex.message.gsub Rails.root.to_s, ''

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
