module EditableBlockHelper

    def display_block (name)
        @editable_block = Admin::EditableBlock.find_by_name(name)
        
        if @editable_block then
          erb = ERB.new(@editable_block.content)
          return erb.result(binding).html_safe
        else
          return "Block not defined"
        end
    end

end
