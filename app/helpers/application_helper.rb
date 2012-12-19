module ApplicationHelper
  def xts_widget(xts_id)
    "<div id='ticketslist' class='xtsprodates'></div>
<script src='http://www.xtspro.com/book/book.js'></script>
<script>XTSPRO.insert_dates('BT', #{xts_id}, '#ticketslist');</script>".html_safe
  end
end
