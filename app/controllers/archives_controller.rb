class ArchivesController < ApplicationController
  layout "archives"

  def index
    @title = "Archives"
  end
end