module AdminHelper
  def user_link_or_text(u)
    if can? :read, u
      link_to u.name_or_email, admin_user_path(u)
    else
      u.name_or_email
    end
  end
end
