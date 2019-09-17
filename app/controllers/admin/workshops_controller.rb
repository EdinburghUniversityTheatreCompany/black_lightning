class Admin::WorkshopsController < AdminController
  load_and_authorize_resource find_by: :slug

  def index
    @title = 'Workshops'
    @workshops = Workshop.paginate(page: params[:page], per_page: 15).all
  end

  def show
    @workshop = Workshop.find_by_slug(params[:id])
    @title = @workshop.name
  end

  def new
    @workshop = Workshop.new
    @users = User.by_first_name.all
    @title = 'New Workshop'
  end

  def create
    @workshop = Workshop.new(workshop_params)
    @users = User.by_first_name.all

    respond_to do |format|
      if @workshop.save
        format.html { redirect_to admin_workshop_url(@workshop), notice: 'Workshop was successfully created.' }
      else
        format.html { render 'new' }
      end
    end
  end

  def edit
    @workshop = Workshop.find_by_slug(params[:id])
    @users = User.by_first_name.all
    @title = "Editing #{@workshop.name}"
  end

  def update
    @workshop = Workshop.find_by_slug(params[:id])
    @users = User.by_first_name.all

    respond_to do |format|
      if @workshop.update_attributes(workshop_params)
        format.html { redirect_to admin_workshop_url(@workshop), notice: 'Workshop was successfully updated.' }
      else
        format.html { render 'edit' }
      end
    end
  end

  def destroy
    @workshop = Workshop.find_by_slug(params[:id])
    @workshop.destroy

    respond_to do |format|
      format.html { redirect_to admin_workshops_url }
      format.json { head :no_content }
    end
  end

  private
  def workshop_params
    params.require(:workshop).permit(:description, :name, :slug, :tagline, :author, :venue, :venue_id, :season,
                                     :season_id, :xts_id, :is_public, :image, :start_date, :end_date, :price,
                                     :spark_seat_slug,
                                     pictures_attributes: [:id, :_destroy, :description, :image],
                                     team_members_attributes: [:id, :_destroy, :position, :user, :user_id, :proposal, :proposal_id, :display_order])
  end
end
