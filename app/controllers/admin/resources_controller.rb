class Admin::ResourcesController < AdminController
  layout 'subpage_sidebar'

  def membership_checker
    @editable_block = Admin::EditableBlock.find_by(url: 'admin/resources/membership_checker')

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
    @controller = 'admin/resources'

    @root_url = helpers.get_subpage_root_url(@controller, params[:page])

    @subpages = helpers.get_subpages(@root_url)
  end
end
