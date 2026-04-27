require "#{Rails.root}/lib/kramdown/parser/b_kramdown"

module MdHelper
  def render_markdown(md)
    return "" if md.blank?

    html = Kramdown::Document.new(md, input: "BKramdown").to_html
    Rails::Html::SafeListSanitizer.new.sanitize(html, tags: %w[
      p h1 h2 h3 h4 h5 h6 br hr
      em strong i b
      ul ol li
      blockquote pre code
      a img
      table thead tbody tfoot tr td th
      div span
    ], attributes: %w[id class href src alt title width height style]).html_safe
  end

  def render_plain(md)
    return "" if md.nil?

    CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(Kramdown::Document.new(md, input: "BKramdown").to_html))
  end

  def truncate_markdown(content, length = 100)
    ActionController::Base.helpers.truncate(render_plain(content).strip, length: length)
  end
end
