##
# Controller for the about pages.
##
class AboutController < ApplicationController
  skip_authorization_check

  def page
    @editable_block = Admin::EditableBlock.find_by!(url: @current_path.delete_prefix("/"))
  end
end
