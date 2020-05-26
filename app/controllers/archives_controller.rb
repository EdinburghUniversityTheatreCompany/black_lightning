class ArchivesController < ApplicationController
  skip_authorization_check
  layout 'archives'

  def index
    @title = 'Archives'
  end
end
