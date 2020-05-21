class Kramdown::Parser::BKramdown < Kramdown::Parser::Kramdown
  def initialize(source, options)
    super
    @options = options
  end

  def handle_extension(name, opts, body, type, _line_no)
    case name
    when 'captioned_image'
      div = Element.new(:html_element, 'div', { class: "captioned-image thumbnail #{opts['class']}" }, category: :block)

      div.children << Kramdown::Parser::Kramdown.parse(body, @options)[0]

      @tree.children << div
      true
    else
      # :nocov:
      super(name, opts, body, type)
      # :nocov:
    end
  end
end
