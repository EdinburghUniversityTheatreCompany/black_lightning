##
# Controller for the about pages.
#
# No actions are defined here. It serves up the files in app/views/about/* using the app/views/layouts/about.html.erb layout.
##
class AboutController < ApplicationController
  skip_authorization_check
  
  layout 'subpage_sidebar'

  def index
    set_subpages('')
    render 'about/overview'
  end

  def page
    if params[:page].nil? || params[:page] == '' || params[:page].downcase == 'overview'
      index
    else
      set_subpages(params[:page])
      begin
        render 'about/' + params[:page]
      rescue ActionView::MissingTemplate
        redirect_to '404', status: 404
      end
    end
  end

  private

  def set_subpages(page)
    @controller = 'about'

    @alias = {
      'eutc' => 'EUTC'
    }

    @root_page = helpers.get_subpage_root_page(page)
    @subpages = helpers.get_subpages(@controller, @root_page)
  end
end
