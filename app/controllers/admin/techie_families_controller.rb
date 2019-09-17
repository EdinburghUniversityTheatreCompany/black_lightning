##
# Responsible for the techie families graph.
# ---
# The sparse-ness of this controller is the result of apathy on my part.
# Use the CLI console to add techies and relationships.
# Maybe someday I'll give it a UI - CS 16/12/12
##
class Admin::TechieFamiliesController < AdminController
  ##
  # GET /admin/techie_families
  ##
  def index
    @title = 'Techie Families'
    @techies = Techie.all
  end

  def show
    @techie = Techie.find(params[:id])
    @title = 'Techie'
  end

  def new
    @techies = Techie.all
    @techie = Techie.new
    @title = 'New Techie'
  end

  def create
    @techies = Techie.all
    @techie = Techie.new(techie_params)

    respond_to do |format|
      if @techie.save
        format.html { redirect_to admin_techie_family_path(@techie), notice: 'Techie was successfully created.' }
      else
        format.html { render 'new' }
      end
    end
  end

  def edit
    @techies = Techie.all
    @techie = Techie.find(params[:id])
    @title = 'Editing Techie'
  end

  def update
    @techies = Techie.all
    @techie = Techie.find(params[:id])

    respond_to do |format|
      if @techie.update_attributes(techie_params)
        format.html { redirect_to admin_techie_family_path(@techie), notice: 'Techie was successfully updated.' }
      else
        format.html { render 'edit' }
      end
    end
  end

  def destroy
    @techie = Techie.find(params[:id])
    @techie.destroy

    respond_to do |format|
      format.html { redirect_to admin_techie_families_path }
      format.json { head :no_content }
    end
  end

  def graph
    @title = 'Techie Families'
    @techies = Techie.all
  end

  private
  def techie_params
    params.require(:techie).permit(:name,
                                   children_attributes: [:id, :_destroy, :name],
                                   parents_attributes: [:id, :_destroy, :name])
  end
end
