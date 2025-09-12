require "#{Rails.root}/lib/kramdown/parser/b_kramdown"

module MdHelper
  def render_markdown(md)
    return "" if md.nil?

    Kramdown::Document.new(md, input: "BKramdown").to_html.html_safe
  end

  def render_plain(md)
    return "" if md.nil?

    ActionController::Base.helpers.strip_tags(Kramdown::Document.new(md, input: "BKramdown").to_html)
  end

  def truncate_markdown(content, length = 100)
    ActionController::Base.helpers.truncate(render_plain(content).strip, length: length)
  end
end
