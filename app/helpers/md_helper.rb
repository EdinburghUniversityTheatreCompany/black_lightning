require "commonmarker"

module MdHelper
  MARKDOWN_OPTIONS = ActionView::Template::Handlers::Markdown::OPTIONS

  IAL_INLINE_PATTERN = /\A(.*?)\s*\{\s*((?:[.#][\w-]+\s*)+)\}\s*\z/m
  IAL_BLOCK_PATTERN  = /\A\{\s*((?:[.#][\w-]+\s*)+)\}\z/

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

    # Pass 1: inline IAL at end of element text, e.g. ## Heading { .class }
    # When the text before { } is blank and the previous sibling is an element
    # (e.g. [link](url){ .class }), apply to that sibling instead of the parent.
    doc.css("p, h1, h2, h3, h4, h5, h6, li, blockquote, td, th").each do |node|
      last = node.children.last
      next unless last&.text?
      if (m = last.content.match(IAL_INLINE_PATTERN))
        target = if m[1].blank? && last.previous_sibling&.element?
          last.previous_sibling
        else
          node
        end
        apply_ial_tokens(target, m[2])
        last.content = m[1]
      end
    end

    # Pass 2: block IAL as a standalone paragraph, e.g. paragraph\n\n{ .class }
    doc.css("p").each do |node|
      if (m = node.text.strip.match(IAL_BLOCK_PATTERN))
        prev = node.previous_element
        apply_ial_tokens(prev, m[1]) if prev
        node.remove
      end
    end

    doc.to_html
  end

  def apply_ial_tokens(element, tokens)
    tokens.scan(/([.#])([\w-]+)/).each do |type, name|
      if type == "."
        existing = element["class"].to_s.split
        element["class"] = (existing + [ name ]).uniq.join(" ")
      else
        element["id"] = name
      end
    end
  end
end
