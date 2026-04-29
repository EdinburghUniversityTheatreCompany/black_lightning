require "commonmarker"

module MdHelper
  MARKDOWN_OPTIONS = {
    parse: { smart: true },
    render: { hardbreaks: true },
    extension: { strikethrough: true, table: true, autolink: true, tagfilter: true }
  }.freeze

  def render_markdown(md)
    return "" if md.blank?

    html = ::Commonmarker.to_html(md, options: MARKDOWN_OPTIONS, plugins: { syntax_highlighter: nil })
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

    CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(
      ::Commonmarker.to_html(md, options: MARKDOWN_OPTIONS, plugins: { syntax_highlighter: nil })
    ))
  end

  def truncate_markdown(content, length = 100)
    ActionController::Base.helpers.truncate(render_plain(content).strip, length: length)
  end
end
