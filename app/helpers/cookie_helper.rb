module CookieHelper
  COOKIE_DOMAIN = :all

  def set_cookie(name, value)
    cookies[name] = { value: value, domain: COOKIE_DOMAIN, secure: true }
  end

  def delete_cookie(name)
    cookies.delete(name, domain: COOKIE_DOMAIN)
  end
end