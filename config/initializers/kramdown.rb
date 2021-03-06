# See https://gist.github.com/1670699

class ActionView::Template
  module Handlers
    class Kramdown
      def call(template, source)
        "Kramdown::Document.new(#{source.inspect}).to_html"
      end
    end
  end

  register_template_handler(:md, Handlers::Kramdown.new)
end
