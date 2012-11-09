module EditableBlockHelper

    def display_block (name, admin_page)
        @editable_block = Admin::EditableBlock.find_by_name(name)

        if not @editable_block then
          return "Block not defined"
        end

        @editable_block.admin_page = admin_page
        @editable_block.save

        if can? :edit, @editable_block then
          return render :partial => "/shared/editable_block_editor"
        else
          return render_markdown(@editable_block.content)
        end
    end

end
