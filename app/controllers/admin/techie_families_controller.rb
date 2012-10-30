class Admin::TechieFamiliesController < AdminController
  def index
    @techies = Techie.all
  end
end
