##
# Controller for the about pages.
##
class AboutController < ApplicationController
  skip_authorization_check
  
  layout 'subpage_sidebar'

  def page
    @controller = 'about'

    root_url = helpers.get_subpage_root_url(@controller, params[:page])

    @editable_block = Admin::EditableBlock.find_by!(url: root_url)

    @subpages = helpers.get_subpages(root_url)
  end
end
