class ArchivesController < ApplicationController
  skip_authorization_check

  def index
    @title = 'Archives'
  end

  def page
    @editable_block = Admin::EditableBlock.find_by!(url: @current_path.delete_prefix('/'))
  end
end
