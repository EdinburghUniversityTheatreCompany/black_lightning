##
#              _,._
#         __.o`   o`"-.
#      .-O o `"-.o   O )_,._
#     ( o   O  o )--.-"`O   o"-.`
#      '--------'  (   o  O    o)
#                   `----------`
#
# EATS YOUR COOKIES. OM NOM NOM.
# ---
# Seriously though, prevents any cookies from leaving the server unless
# you are trying to sign in or you have allowed cookies.
##
class CookieKiller
  ##
  # Store the app variable so we can use it later.
  ##
  def initialize(app)
    @app = app
  end

  ##
  # On each request, checks if cookies have been allowed or if the user is
  # trying to sign in (/users/) or activate their account (/membership_activation_tokens/).
  # If not, deletes all cookies.
  ##
  def call(env)
    status, headers, body = @app.call(env)

    request = ActionDispatch::Request.new(env)
    unless request.cookie_jar[:allow_cookies] || env['PATH_INFO'].include?('/users/') || env['PATH_INFO'].include?('/membership_activation_tokens/')
      # remove ALL cookies from the response
      headers.delete 'Set-Cookie'
    end

    [status, headers, body]
  end
end

Rails.application.config.middleware.insert_before ::ActionDispatch::Cookies, ::CookieKiller
