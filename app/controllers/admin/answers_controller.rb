##
# Responsible for serving up files associated with answers
##
class Admin::AnswersController < ApplicationController
  load_resource
  ##
  # Returns the file associated with the answer, checking the user has
  # permission to read the answer.
  ##
  def get_file
    answerable = @answer&.answerable
    authorize!(:show, answerable)

    # I have no clue why this is necessary and why authorize! doesn't just work.
    raise(CanCan::AccessDenied) if current_user.cannot?(:show, answerable)

    send_file @answer.file.path, x_sendfile: true, type: @answer.file.content_type, disposition: 'attachment', filename: @answer.file.original_filename
  end
end
