require "commonmarker"

module MdHelper
  MARKDOWN_OPTIONS = ActionView::Template::Handlers::Markdown::OPTIONS

  # A single IAL token: a `.class`, an `#id`, or a `key="value"` attribute (the
  # kramdown attribute syntax, e.g. `style="font-size:150%"`). Quotes may be the
  # curly variants because smart-punctuation rewrites straight quotes first.
  DQUOTE = '"“”'
  SQUOTE = "'‘’"
  IAL_TOKEN = /[.#][\w-]+|[\w-]+\s*=\s*[#{DQUOTE}][^#{DQUOTE}]*[#{DQUOTE}]|[\w-]+\s*=\s*[#{SQUOTE}][^#{SQUOTE}]*[#{SQUOTE}]/
  IAL_INLINE_PATTERN = /\A(.*?)\s*\{\s*:?\s*((?:#{IAL_TOKEN}\s*)+)\}\s*\z/m
  IAL_BLOCK_PATTERN  = /\A\{\s*:?\s*((?:#{IAL_TOKEN}\s*)+)\}\z/

  def render_markdown(md)
    return "" if md.blank?

    html = ::Commonmarker.to_html(md, options: MARKDOWN_OPTIONS, plugins: { syntax_highlighter: nil })
    html = apply_ial(html)
    sanitized = Rails::Html::SafeListSanitizer.new.sanitize(html, tags: %w[
      p h1 h2 h3 h4 h5 h6 br hr
      em strong i b
      ul ol li
      blockquote pre code
      a img
      table thead tbody tfoot tr td th
      div span
      iframe
      details summary
    ], attributes: %w[id class href src alt title width height style frameborder allowfullscreen allow])
    %(<div class="markdown-body prose max-w-none">#{sanitized}</div>).html_safe
    # Note that these classes are also added in the markdown_editor_controller to the preview rendered there
    # so it matches. Search for previewContents.classList
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

  private

  def apply_ial(html)
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    # Pass 1: IAL at the end of a block's text.
    doc.css("p, h1, h2, h3, h4, h5, h6, li, blockquote, td, th").each do |node|
      last = node.children.last
      next unless last&.text?
      next unless (m = last.content.match(IAL_INLINE_PATTERN))

      prev = last.previous_sibling
      if m[1].present?
        # "## Heading { .class }" — attributes on this block.
        apply_ial_tokens(node, m[2])
        last.content = m[1]
      elsif prev&.element? && prev.name != "br"
        # "[link](url){ .class }" — attributes on the trailing inline element.
        apply_ial_tokens(prev, m[2])
        last.content = m[1]
      elsif prev&.name == "br"
        # "paragraph text\n{: .class }" — soft break then a block IAL for this
        # paragraph. Drop the break and apply to the paragraph itself.
        prev.remove
        apply_ial_tokens(node, m[2])
        last.content = ""
      end
      # else: the block is nothing but the IAL — left for Pass 2 below.
    end

    # Pass 2: a block whose only content is an IAL styles the PRECEDING block,
    # e.g. `paragraph\n\n{ .class }` or `# Heading\n{:.class}`.
    doc.css("p").each do |node|
      next unless (m = node.text.strip.match(IAL_BLOCK_PATTERN))

      prev = node.previous_element
      apply_ial_tokens(prev, m[1]) if prev
      node.remove
    end

    doc.to_html
  end

  def apply_ial_tokens(element, tokens)
    tokens.scan(IAL_TOKEN).each do |token|
      case token
      when /\A\.(.+)\z/
        element["class"] = (element["class"].to_s.split + [ $1 ]).uniq.join(" ")
      when /\A#(.+)\z/
        element["id"] = $1
      when /\A([\w-]+)\s*=\s*[#{DQUOTE}]([^#{DQUOTE}]*)[#{DQUOTE}]\z/, /\A([\w-]+)\s*=\s*[#{SQUOTE}]([^#{SQUOTE}]*)[#{SQUOTE}]\z/
        element[$1] = $2
      end
    end
  end
end
