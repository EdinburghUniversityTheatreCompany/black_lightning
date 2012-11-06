class AttachmentsController < ApplicationController
  def show
    @attachment = Attachment.find_by_name(params[:id])
    
    if @attachment.editable_block.admin_page then
      authorize! :access, :backend
    end
    
    redirect_to @attachment.file.url
  end
end
