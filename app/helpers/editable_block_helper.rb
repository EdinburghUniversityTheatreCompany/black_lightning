module EditableBlockHelper

    def display_block (name, admin_page)
        @editable_block = Admin::EditableBlock.find_by_name(name)
        
        @editable_block.admin_page = admin_page
        @editable_block.save
        
        if @editable_block then
          return render_markdown(@editable_block.content)
        else
          return "Block not defined"
        end
    end

end
