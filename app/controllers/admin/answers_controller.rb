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

    return redirect_to '404', status: 404 unless @answer.question.response_type.downcase == 'file'

    response.headers["Content-Type"] = @answer.file.content_type
    response.headers["Content-Disposition"] = "attachment; #{@answer.file.filename}"

    @answer.file.download do |chunk|
      response.stream.write(chunk)
    end
  end
end
