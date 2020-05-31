##
# Controller for the get_involved pages.
#
# No actions are defined here. It serves up the files in app/views/get_involved/* using the app/views/layouts/get_involved.html.erb layout.
##
class GetInvolvedController < ApplicationController
  skip_authorization_check

  layout 'subpage_sidebar'

  def index
    set_subpages('')
    render 'get_involved/overview'
  end

  def page
    @opportunities = Opportunity.active if params[:page] == 'opportunities'

    if params[:page].nil? || params[:page] == '' || params[:page].downcase == 'overview'
      index
    else
      set_subpages(params[:page])
      begin
        render 'get_involved/' + params[:page]
      rescue ActionView::MissingTemplate
        redirect_to '404', status: 404
      end
    end
  end

  private

  def set_subpages(page)
    @controller = 'get_involved'

    @alias = {
      'ssw' => 'Stage, Set and Wardrobe'
    }

    @root_page = helpers.get_subpage_root_page(page)
    @subpages = helpers.get_subpages(@controller, @root_page)
  end
end
