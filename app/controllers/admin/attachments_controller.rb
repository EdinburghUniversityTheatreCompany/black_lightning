##
# Admin controller for User management.
##
class Admin::AttachmentsController < AdminController
  include GenericController

  load_and_authorize_resource

  ##
  # Overrides load_index_resources
  ##

  private

  def base_index_query
    @q = @attachments.includes(:item).ransack(params[:q])
    @attachments = @q.result(distinct: true)

    return @attachments
  end
end
