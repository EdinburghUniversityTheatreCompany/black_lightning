##
# Controller for Admin::EditableBlock. More details can be found there.
##

class Admin::EditableBlocksController < AdminController
  include GenericController

  load_and_authorize_resource

  ##
  # GET /admin/editable_blocks/new
  #
  # GET /admin/editable_blocks/new.json
  ##
  def new
    # The title is set by the view, sometimes.
    @editable_block.name = params[:name]

    super
  end

  private

  def resource_class
    Admin::EditableBlock
  end

  def permitted_params
    [
      :content, :name, :url, :ordering, :admin_page, :group, 
      attachments_attributes: [:id, :_destroy, :name, :file, :access_level, attachment_tag_ids: []]
    ]
  end

  def order_args
    ['group', 'name']
  end
end
