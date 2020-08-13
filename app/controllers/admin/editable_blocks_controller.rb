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
    # The title is set by the view.
    @editable_block.name = params[:name]

    super
  end

  private

  def resource_class
    Admin::EditableBlock
  end

  def load_index_resources
    @editable_blocks = @editable_blocks.order(order_args).group_by(&:group)

    return @editable_blocks
  end

  def permitted_params
    [:content, :name, :url, :ordering, :admin_page, :group, attachments_attributes: [:id, :_destroy, :name, :file]]
  end

  def update_redirect_url
    admin_editable_blocks_url
  end

  def create_redirect_url
    update_redirect_url
  end

  def order_args
    :name
  end
end
