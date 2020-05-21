class Admin::ResourcesController < AdminController
  layout 'subpage_sidebar'

  def index
    set_subpages('')
    render 'admin/resources/overview'
  end

  def page
    if params[:page].nil? || params[:page] == '' || params[:page].downcase == 'overview'
      index
    else
      set_subpages(params[:page])
      begin
        render 'admin/resources/' + params[:page]
      rescue ActionView::MissingTemplate
        redirect_to '404', status: 404
      end
    end
  end

  private

  def set_subpages(page)
    @controller = 'admin/resources'
    @root_page = helpers.get_subpage_root_page(page)
    @subpages = helpers.get_subpages(@controller, @root_page)
  end
end
