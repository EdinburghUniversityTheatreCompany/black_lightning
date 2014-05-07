module ApplicationHelper
  def xts_widget(xts_id)
    "<div id='tickets-#{xts_id}' class='xtsprodates'></div>
<script src='http://www.xtspro.com/book/book.js'></script>
<script>XTSPRO.insert_dates('BT', #{xts_id}, '#tickets-#{xts_id}');</script>".html_safe
  end

  def spark_seat_widget(spark_seat_slug)
    """
      <div class=\"spark-container\" data-event-slug=\"#{spark_seat_slug}\">
        One moment please...
      </div>
      <script src='https://www.sparkseat.com/assets/widget/loader.js'></script>
    """.html_safe
  end

  def strip_tags(html)
      return self.gsub(%r{</?[^>]+?>}, '')
  end
end
