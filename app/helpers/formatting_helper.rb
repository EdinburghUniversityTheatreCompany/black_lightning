module FormattingHelper
  def format(content, tag)
    if content.is_a? Array
      return content.map { |item| "<#{tag}>#{item}</#{tag}>".html_safe }
    else
      return "<#{tag}>#{item}</#{tag}>".html_safe
    end
  end

  def escape_line_breaks(content)
    return content&.gsub(/[\r\n]+/, "<br />")&.html_safe 
  end
end
