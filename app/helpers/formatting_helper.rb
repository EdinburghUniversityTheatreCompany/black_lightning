module FormattingHelper
  def escape_line_breaks(content)
    return content&.gsub(/[\r\n]+/, "<br />")&.html_safe 
  end
end
