class ArchivesController < ApplicationController
  include EditableBlockPage

  skip_authorization_check

  def index
    @title = "Archives"
    @meta[:description] = "Decades of Edinburgh student theatre: every show, workshop and season the EUTC has staged at Bedlam Theatre."
  end

  def page
    @editable_block = Admin::EditableBlock.find_by!(url: @current_path.delete_prefix("/"))

    set_meta_from_editable_block
  end
end
