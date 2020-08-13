class Admin::ResourcesController < AdminController
  layout 'subpage_sidebar'

  def page
    @controller = 'admin/resources'

    root_url = helpers.get_subpage_root_url(@controller, params[:page])

    @editable_block = Admin::EditableBlock.find_by(url: root_url)

    if @editable_block.nil?
      redirect_to '404', status: 404
      return
    end

    @subpages = helpers.get_subpages(root_url)
  end
end
