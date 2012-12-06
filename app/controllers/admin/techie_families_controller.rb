class Admin::TechieFamiliesController < AdminController
  def index
    @title = "Techie Families"
    @techies = Techie.all
  end
end
