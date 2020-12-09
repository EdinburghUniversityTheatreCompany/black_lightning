module CookieHelper
  COOKIE_DOMAIN = :all

  def set_cookie(name, value, options: {})
    options[:same_site] ||= :lax
    cookies[name] = { value: value, domain: COOKIE_DOMAIN, **options }
  end

  def delete_cookie(name)
    cookies.delete(name, domain: COOKIE_DOMAIN)
  end
end