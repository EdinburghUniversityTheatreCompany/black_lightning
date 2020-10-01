##
# Controller for Admin::EditableBlock. More details can be found there.
##

class Admin::EditableBlocksController < AdminController
  include GenericController

  load_and_authorize_resource

  def show
    if @editable_block.url.present? && (!@editable_block.content.present? || !@editable_block.content.start_with?(SubpageHelper::EXTERNAL_URL_PREFIX))
      redirect_to "/#{@editable_block.url}"
      return
    end

    super
  end

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
    @editable_blocks = super.group_by(&:group)

    return @editable_blocks
  end

  def permitted_params
    [:content, :name, :url, :ordering, :admin_page, :group, attachments_attributes: [:id, :_destroy, :name, :file]]
  end

  def order_args
    [:url, :name]
  end

  def should_paginate
    false
  end
end
