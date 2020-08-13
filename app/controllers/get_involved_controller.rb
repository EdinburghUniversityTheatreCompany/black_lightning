##
# Controller for the get_involved pages.
#
# The pages are all defined as Editable Blocks.
##
class GetInvolvedController < ApplicationController
  skip_authorization_check

  layout 'subpage_sidebar'

  def opportunities
    @opportunities = Opportunity.active

    set_subpages
  end

  def page
    set_subpages

    @editable_block = Admin::EditableBlock.find_by(url: @root_url)

    if @editable_block.nil?
      redirect_to '404', status: 404
      return
    end
  end

  private

  def set_subpages
    @controller = 'get_involved'

    @root_url = helpers.get_subpage_root_url(@controller, params[:page])

    @subpages = helpers.get_subpages(@root_url)
  end
end
