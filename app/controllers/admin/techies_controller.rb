##
# Responsible for the techie family tree.
##
class Admin::TechiesController < AdminController
  load_and_authorize_resource
  ##
  # GET /admin/techies
  ##
  def index
    @title = 'Techie Families'
  end

  def show
    @title = @techie.name
  end

  def new
    set_form_params
  end

  def create
    set_form_params

    respond_to do |format|
      if @techie.save
        format.html { redirect_to admin_techie_path(@techie), notice: 'Techie was successfully created.' }
      else
        format.html { render 'new', status: :unprocessable_entity }
      end
    end
  end

  def edit
    set_form_params
  end

  def update
    set_form_params

    respond_to do |format|
      if @techie.update(techie_params)
        format.html { redirect_to admin_techie_path(@techie), notice: 'Techie was successfully updated.' }
      else
        format.html { render 'edit', status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @techie = Techie.find(params[:id])
    helpers.destroy_with_flash_message(@techie)

    respond_to do |format|
      format.html { redirect_to admin_techies_path }
      format.json { head :no_content }
    end
  end

  def tree
    @title = 'Techie Families'
    @techies = Techie.all.includes(:children, :parents)
  end

  private

  def set_form_params
    @techies_collection = Techie.where.not(id: @techie.id).pluck(:name, :id)
  end

  def techie_params
    params.require(:techie).permit(:name,
                                   children_attributes: [:id, :_destroy, :name],
                                   parents_attributes: [:id, :_destroy, :name])
  end
end
