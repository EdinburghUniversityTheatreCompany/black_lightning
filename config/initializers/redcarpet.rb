#See https://gist.github.com/1670699

class ActionView::Template
  module Handlers
    class Markdown
      def call(template)
        "Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(#{template.source.inspect})"
      end
    end
  end

  register_template_handler(:md, Handlers::Markdown.new)
end