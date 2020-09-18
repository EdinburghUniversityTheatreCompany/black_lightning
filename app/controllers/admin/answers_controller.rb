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
    authorize!(:show, @answer&.answerable)

    raise(ActiveRecord::RecordNotFound.new('The specified answer is not a file')) unless @answer.question.response_type.downcase == 'file'

    response.headers["Content-Type"] = @answer.file.content_type
    response.headers["Content-Disposition"] = "attachment; #{@answer.file.filename}"

    @answer.file.download do |chunk|
      response.stream.write(chunk)
    end
  end
end
