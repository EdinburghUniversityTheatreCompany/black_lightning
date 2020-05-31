module EditableBlockHelper
  def display_block(name, admin_page)
    @editable_block = Admin::EditableBlock.find_by_name(name)

    if @editable_block.nil?
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

    return render partial: '/editable_blocks/display'
  end

  def block_exists(name)
    @editable_block = Admin::EditableBlock.find_by_name(name)

    return @editable_block.present?
  end
end
