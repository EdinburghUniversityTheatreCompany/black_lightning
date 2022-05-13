module FormattingHelper
  def format(content, tag)
    if content.is_a? Array
      return content.map { |item| "<#{tag}>#{item}</#{tag}>".html_safe }
    else
      return "<#{tag}>#{item}</#{tag}>".html_safe
    end
  end
end
