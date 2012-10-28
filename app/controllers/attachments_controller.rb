class AttachmentsController < ApplicationController
  def show
    @attachment = Attachment.find_by_name(params[:id])
    
    redirect_to @attachment.file.url
  end
end
