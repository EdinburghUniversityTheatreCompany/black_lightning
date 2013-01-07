module EditableBlockHelper

    def display_block (name, admin_page)
        @editable_block = Admin::EditableBlock.find_by_name(name)

        if not @editable_block then
          if can? :create, Admin::EditableBlock then
            return ("Block not defined. " + link_to('Create Block', new_admin_editable_block_path(:name => name))).html_safe
          else
            return "Block not defined"
          end
        end

        if @editable_block.admin_page != admin_page
          @editable_block.admin_page = admin_page
          @editable_block.save!
        end

        if can? :edit, @editable_block then
          return render :partial => "/shared/editable_block_editor"
        else
          return render_markdown(@editable_block.content)
        end
    end

    def block_exists (name)
        @editable_block = Admin::EditableBlock.find_by_name(name)

        if @editable_block and @editable_block.content.length > 0 then
          return true
        else
          return false
        end
    end

end
