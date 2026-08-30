##
# Controller for the about pages.
##
class AboutController < ApplicationController
  include EditableBlockPage

  skip_authorization_check

  def page
    @editable_block = Admin::EditableBlock.find_by!(url: @current_path.delete_prefix("/"))

    set_meta_from_editable_block
  end
end
