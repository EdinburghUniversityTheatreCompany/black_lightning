module FormattingHelper
  def escape_line_breaks(content)
    return content&.gsub(/[\r\n]+/, "<br />")&.html_safe 
  end

  def render_as_list(list, wrap_tag)
    list.map! { |item| ActionController::Base.helpers.sanitize(item) }
    "<#{wrap_tag}><li>#{list.join('</li><li>')}</li></#{wrap_tag}>".html_safe
  end
end
