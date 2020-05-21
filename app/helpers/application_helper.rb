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
      return '', ''
    end
  end

  # It's a bit hacky, but it works. 
  # Used by the error pages to decide the layout to use
  # Cannot be unit tested because a request needs to be present :/
  # It does not really matter if it renders the wrong layout though.

  def current_environment
    return 'admin' if request.fullpath[0..6].include? 'admin'

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
  end

  # These probably should live somewhere else

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

  def strip_tags(html)
    return html.gsub(%r{</?[^>]+?>}, '')
  end
end
