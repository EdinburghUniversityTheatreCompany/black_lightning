##
# Responsible for serving up files associated with answers
##
class Admin::AnswersController < ApplicationController

  ##
  # Returns the file associated with the answer, checking the user has
  # permission to read the answer.
  ##
  def get_file
    @answer = Admin::Answer.find(params[:id])

    authorize! :read, @answer

    send_file @answer.file.path, :x_sendfile => true, :type => @answer.file.content_type, :disposition => "attachment", :filename => @answer.file.original_filename
  end
end
