class Kramdown::Parser::BKramdown < Kramdown::Parser::Kramdown
  def initialize(source, options)
    super
    @options = options
  end

  # BOOTSTRAP NICETOHAVE: Kramdown images also need to reserve space to prevent content reflow. Not sure where to start.
  # There might be something in the shared_additions file.

  def handle_extension(name, opts, body, type, _line_no)
    case name
    when 'captioned_image'
      div = Element.new(:html_element, 'div', { class: "captioned-image img-thumbnail #{opts['class']}" }, category: :block)

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
