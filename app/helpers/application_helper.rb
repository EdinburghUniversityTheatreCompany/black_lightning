module ApplicationHelper
  # It's a bit hacky, but it works.
  # Used by the error pages and subpage layout to decide which layout to use.
  def current_environment(path)
    return 'admin' if path[0..6].include?('admin') && current_ability.can?(:access, :backend)

    return 'application'
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
