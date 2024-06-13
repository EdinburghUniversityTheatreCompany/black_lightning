module ApplicationHelper
  def bool_icon(bool)
    return bool ? '&#10004;'.html_safe : '&#10008;'.html_safe
  end

  def bool_text(bool, capitalized = true)
    word = bool ? 'yes' : 'no'

    return word.upcase_first if capitalized

    return word
  end

  def html_alert_info(key)
    case key.to_sym
    when :alert, :error
      return 'alert-danger', 'fas fa-exclamation-circle'
    when :success
      return 'alert-success', 'fas fa-check-circle'
    when :notice
      return 'alert-info', 'fas fa-info-circle'
    else
      return 'alert-info', 'fas fa-info-circle'
    end
  end

  def swal_alert_info(key)
    case key.to_sym
    when :error
      return 'error'
    when :alert
      return 'warning'
    when :success
      return 'success'
    when :notice
      return 'info'
    else
      return 'info'
    end
  end

  # It's a bit hacky, but it works.
  # Used by the error pages and subpage layout to decide which layout to use.
  def current_environment(path)
    return 'admin' if path[0..6].include?('admin') && current_ability.can?(:access, :backend)

    return 'application'
  end

  def append_to_flash(key, message)
    if flash[key].blank?
      flash[key] = [message]
    elsif flash[key].is_a? Enumerable
      flash[key] << message
    else
      flash[key] = [flash[key], message]
    end

    flash[key] = flash[key].uniq
  end

  # Turns all flash messages into arrays, merges 'alerts' into 'errors', and merges 'notices' in to 'successes'.
  def format_flash
    # Convert each flash type into an array if it is not already.
    # The to_h is to make a local copy so we can assign to the real flash.
    # If you do not do this, it would say you cannot assign during iteration
    # and because flash is not a real hash, it does not have all methods and you
    # cannot perform in-place operations.
    flash.to_h.each{ |key, value| flash[key] = Array(value) }

    # Alert is just an alias for error, so merge them here.
    flash[:error] += flash[:alert] if flash[:alert].present?
    flash.delete(:alert)

    # Similarly for success
    flash[:success] += flash[:notice] if flash[:notice].present?
    flash.delete(:notice)
  end

  def merge_hash(a, b)
    return a.merge(b) do |_key, oldval, newval|
      # http://stackoverflow.com/a/11171921
      (newval.is_a?(Array) ? (oldval + newval) : (oldval << newval)).uniq
    end
  end

  # These should probably live somewhere else

  def xts_widget(xts_id)
    "<div id='tickets-#{xts_id}' class='xtsprodates'></div>
<script src='http://www.xtspro.com/book/book.js'></script>
<script>XTSPRO.insert_dates('BT', #{xts_id}, '#tickets-#{xts_id}');</script>".html_safe
  end

  def spark_seat_widget(spark_seat_slug)
    ''"
      <div class=\"spark-container\" data-event-slug=\"#{spark_seat_slug}\" data-load-styles=\"bootstrap2\">
        One moment please...
      </div>
      <script src='https://book.sparkseat.com/scripts/loader.js' crossorigin='anonymous'></script>
    "''.html_safe
  end
end
