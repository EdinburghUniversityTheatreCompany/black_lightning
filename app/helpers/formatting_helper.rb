module FormattingHelper
  def escape_line_breaks(content)
    content&.gsub(/[\r\n]+/, "<br />")&.html_safe
  end

  def render_as_list(list, wrap_tag)
    # Sanitize each item in the list to prevent XSS attacks.
    list.map! { |item| ActionController::Base.helpers.sanitize(item) }

    content_tag(wrap_tag) do
      list.map { |item| content_tag(:li, item) }.join.html_safe
    end
  end

  def bool_icon(bool)
    bool ? "&#10004;".html_safe : "&#10008;".html_safe
  end

  def bool_text(bool, capitalized = true)
    word = bool ? "yes" : "no"

    return word.upcase_first if capitalized

    word
  end
end
