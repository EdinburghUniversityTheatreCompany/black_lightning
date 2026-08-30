require "commonmarker"

module MdHelper
  # Explicit rather than relying on views mixing every helper together: render_markdown and
  # render_plain are also called straight off `helpers` from controllers.
  include LinkNormalisationHelper

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
    %(<div class="markdown-body prose max-w-none">#{normalise_hrefs(sanitized)}</div>).html_safe
    # Note that these classes are also added in the markdown_editor_controller to the preview rendered there
    # so it matches. Search for previewContents.classList
  end

  ##
  # A link target typed without a scheme ("theimproverts.co.uk") is a relative path to a browser,
  # so it resolved against the site root and 404ed. Fixed here rather than row by row, because a
  # content editor can type one at any time.
  ##
  def normalise_hrefs(html)
    fragment = Nokogiri::HTML5.fragment(html)

    fragment.css("a[href]").each { |anchor| anchor["href"] = normalise_link_target(anchor["href"]) }

    fragment.to_html
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
      last = ial_text_node(node)
      next unless last&.text?
      next unless (m = last.content.match(IAL_INLINE_PATTERN))

      prev = last.previous_sibling
      if m[1].present?
        # "## Heading { .class }" — attributes on this block.
        apply_ial_tokens(node, m[2])
        last.content = m[1]
        realign_heading_anchor(node)
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
      if prev
        apply_ial_tokens(prev, m[1])
        realign_heading_anchor(prev)
      end
      node.remove
    end

    doc.to_html
  end

  # commonmarker >= 2.9 renders a heading's self-link AFTER the text
  # (`<h2 id="slug">Text<a class="anchor"></a></h2>`; 2.8 put it first), so the
  # text node carrying a trailing IAL is the second-to-last child, not the last.
  def ial_text_node(node)
    children = node.children
    heading_anchor?(children.last) ? children[-2] : children.last
  end

  # An `{ #id }` IAL renames the heading commonmarker already pointed its
  # self-link at, so the link has to follow or it dangles.
  def realign_heading_anchor(node)
    anchor = node.children.last
    return unless heading_anchor?(anchor) && node["id"].present?

    anchor["href"] = "##{node['id']}"
  end

  def heading_anchor?(node)
    node&.element? && node.name == "a" && node["class"].to_s.split.include?("anchor")
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
