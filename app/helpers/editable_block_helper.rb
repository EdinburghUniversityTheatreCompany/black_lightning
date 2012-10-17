module EditableBlockHelper

    def display_block (name)
        @editable_block = Admin::EditableBlock.find_by_name(name)
        
        if @editable_block then
          return render_markdown(@editable_block.content)
        else
          return "Block not defined"
        end
    end

end
