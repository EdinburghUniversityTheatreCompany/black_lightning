module Admin::SharedDebtHelper
  include CookieHelper
  
  def shared_debt_load(debts, show_non_members, params, includes)
    debt_class = debts.klass
    key = debt_class.table_name

    show_fulfilled, is_specific_user = shared_debt_is_specific_user(debt_class, params[:user_id])

    if is_specific_user
      # In this case, the debts should not be searched. Clear the cookies to prevent a query from being loaded the next time the index is opened.
      shared_debt_clear_params(key)

      debts = debts.where(user_id:params[:user_id]) if params[:user_id].present?

      q_param = {}
      # Show fulfilled is already set.
    else
      # Gets the search params from the params or the cookies and sets the cookies again.
      q_param = shared_debt_search_params(params, key)
      show_fulfilled = shared_debt_show_fulfilled_param(params, key)
    end

    q = shared_debt_ransack(debts, q_param)

    debts = q.result.includes(*includes)

    debts = debts.unfulfilled unless show_fulfilled
    debts = debts.where(user: Role.find_by(name: :member).users.ids) unless show_non_members == '1'
    debts = debts.page(params[:page]).per(30)

    return debts, q, show_fulfilled, is_specific_user
  end

  def shared_debt_search_params(params, key)
    q_param = params[:q]

    # Load the cookie param if there is no query set.
    begin
      cookie_value = cookies["#{key}_query"]
      q_param ||= JSON.parse(cookie_value.gsub('=>', ':')) if cookie_value.present?
    # :nocov:
    rescue JSON::ParserError => e
      # It's not the worst thing in the world if an error happens, but logging will be useful.
      # If people start to tamper with the cookie, which I don't expect to happen,
      # and the errors become a nuisance, we can disable it.

      Honeybadger.notify(e)
    # :nocov:
    end

    q_param ||= {}

    set_cookie("#{key}_query", q_param)

    return q_param
  end

  def shared_debt_show_fulfilled_param(params, key)
    # Also get the show_fulfilled setting from a cookie if it is not specified.
    show_fulfilled_param = params.fetch(:show_fulfilled, nil)

    show_fulfilled = if show_fulfilled_param.present?
      show_fulfilled_param == '1'
    else 
      cookies["#{key}_show_fulfilled"] == 'true'
    end

    set_cookie("#{key}_show_fulfilled", show_fulfilled.to_s)

    return show_fulfilled
  end

  def shared_debt_clear_params(key)
    delete_cookie("#{key}_query")
    delete_cookie("#{key}_show_fulfilled")
  end

  def shared_debt_ransack(debts, q_param)
    q = debts.ransack(q_param, auth_object: current_ability)

    q.sorts = ['due_by asc', 'show_name asc', 'user_full_name asc'] if q.sorts.empty?

    return q
  end

  def shared_debt_is_specific_user(debt_class, user_id)
    if user_id.present?
      # If we are just displaying one user, also display the fulfilled debts even if the box was not ticked.
      is_specific_user = true
      show_fulfilled = true
    elsif debt_class.accessible_by(current_ability).map { |debt| debt.user.id }.uniq.count < 2
      is_specific_user = true
      show_fulfilled = true
    else
      is_specific_user = false
      show_fulfilled = false
    end

    return show_fulfilled, is_specific_user
  end
end
