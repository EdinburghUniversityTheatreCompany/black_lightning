class ArchivesController < ApplicationController
  skip_authorization_check

  def index
    @title = 'Archives'
  end
end
