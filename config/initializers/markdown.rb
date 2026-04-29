require "commonmarker"

class ActionView::Template
  module Handlers
    class Markdown
      OPTIONS = {
        parse: { smart: true },
        render: { hardbreaks: true },
        extension: { strikethrough: true, table: true, autolink: true, tagfilter: true }
      }.freeze

      def call(template, source)
        "Commonmarker.to_html(#{source.inspect}, options: #{OPTIONS.inspect}, plugins: { syntax_highlighter: nil }).html_safe"
      end
    end
  end

  register_template_handler(:md, Handlers::Markdown.new)
end
