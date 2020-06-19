module EditableBlockHelper
  def display_block(name, admin_page, display_edit = true)
    @editable_block = Admin::EditableBlock.find_by_name(name)

    if @editable_block.nil?
      if current_ability.can?(:create, Admin::EditableBlock)
        return ('Block not defined. ' + link_to('Create Block', new_admin_editable_block_path(name: name))).html_safe
      else
        return 'Block not defined'
      end
    end

    if @editable_block.admin_page != admin_page
      @editable_block.admin_page = admin_page
      @editable_block.save!
    end
    
    # Will only actually display edit if the user also has permission to edit the block.
    return render partial: '/editable_blocks/display', locals: { display_edit: display_edit }
  end

  def block_exists(name)
    return Admin::EditableBlock.find_by_name(name).present?
  end
end
