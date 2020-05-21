module ApplicationHelper
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

  def strip_tags(_html)
    return gsub(%r{</?[^>]+?>}, '')
  end
end
