module ApplicationHelper
  def xts_widget(xts_id)
    "<div id='tickets-#{xts_id}' class='xtsprodates'></div>
<script src='http://www.xtspro.com/book/book.js'></script>
<script>XTSPRO.insert_dates('BT', #{xts_id}, '#tickets-#{xts_id}');</script>".html_safe
  end
  def strip_tags(html)
      return self.gsub(%r{</?[^>]+?>}, '')
  end
end
