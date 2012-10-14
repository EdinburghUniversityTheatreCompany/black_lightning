module EditableBlockHelper

    def display_block (name)
        @editable_block = Admin::EditableBlock.find_by_name(name)
        
        if @editable_block then
          require 'redcarpet'
          renderer = Redcarpet::Render::HTML.new
          redcarpet = Redcarpet::Markdown.new(renderer, {})
          return redcarpet.render(@editable_block.content).html_safe
        else
          return "Block not defined"
        end
    end

end
