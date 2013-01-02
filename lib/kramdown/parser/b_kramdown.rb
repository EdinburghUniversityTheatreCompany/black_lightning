class Kramdown::Parser::BKramdown < Kramdown::Parser::Kramdown

  def initialize(source, options)
     super
     @options = options
   end

  def handle_extension(name, opts, body, type)
    case name
    when 'captioned_image' 
      div = Element.new(:html_element, "div", {:class => "captioned-image thumbnail #{opts["class"]}" }, { :category => :block })
       
      div.children << Kramdown::Parser::Kramdown.parse(body, @options)[0]
       
      @tree.children << div
      true
    else
      super(name, opts, body, type)
    end
  end 

end