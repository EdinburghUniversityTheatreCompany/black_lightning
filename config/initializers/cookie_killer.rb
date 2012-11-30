class CookieKiller
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)

    request = ActionDispatch::Request.new(env)
    if not (request.cookie_jar[:allow_cookies] or env['PATH_INFO'] == '/users/sign_in') then
      # remove ALL cookies from the response
      headers.delete 'Set-Cookie'
    end

    [status, headers, body]
  end
end

Rails.application.config.middleware.insert_before ::ActionDispatch::Cookies, ::CookieKiller