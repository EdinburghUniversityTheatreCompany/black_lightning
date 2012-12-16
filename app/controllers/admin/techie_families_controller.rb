class Admin::TechieFamiliesController < AdminController
  #The sparse-ness of this controller is the result of apathy on my part. Use the CLI console to add techies and relationships. Maybe someday I'll give it a UI - CS 16/12/12
  def index
    @title = "Techie Families"
    @techies = Techie.all
  end
end
