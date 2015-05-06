module EditableBlockHelper
  def display_block(name, admin_page)
    @editable_block = Admin::EditableBlock.find_by_name(name)

    unless @editable_block
      if can? :create, Admin::EditableBlock
        return ('Block not defined. ' + link_to('Create Block', new_admin_editable_block_path(name: name))).html_safe
      else
        return 'Block not defined'
      end
    end

    if @editable_block.admin_page != admin_page
      @editable_block.admin_page = admin_page
      @editable_block.save!
    end

    if can? :edit, @editable_block
      return render partial: '/shared/editable_block_editor'
    else
      return render_markdown(@editable_block.content)
    end
  end

  def block_exists(name)
    @editable_block = Admin::EditableBlock.find_by_name(name)

    if @editable_block && @editable_block.content.length > 0
      return true
    else
      return false
    end
  end
end
