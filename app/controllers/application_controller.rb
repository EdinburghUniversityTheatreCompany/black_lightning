class ApplicationController < ActionController::Base
  protect_from_forgery
  
  rescue_from CanCan::AccessDenied do |exception|
    redirect_to access_denied_path, :notice => exception.message
  end

  def authorize_backend!
    authorize! :access, :backend
  end
  
  # See http://railscasts.com/episodes/127-rake-in-background
  def call_rake(task, options = {})
    options[:rails_env] ||= Rails.env
    args = options.map { |n, v| "#{n.to_s.upcase}='#{v}'" }
    
    rake_str = "rake #{task} #{args.join(' ')} --trace 2>&1 >> #{Rails.root}/log/rake.log"
    
    if Kernel.is_windows?
      system "start #{rake_str}"
    else
      system "#{rake_str} &"
    end
  end
  
  # Returns true if we are running on a MS windows platform, false otherwise.
  def Kernel.is_windows?
    processor, platform, *rest = RUBY_PLATFORM.split("-")
    platform == 'mswin32'
  end

end
