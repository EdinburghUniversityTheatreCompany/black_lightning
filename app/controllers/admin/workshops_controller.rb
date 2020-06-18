class Admin::WorkshopsController < AdminController
  load_and_authorize_resource find_by: :slug
  skip_load_resource only: %i[index]

  # GET /admin/shows
  # GET /admin/shows.json
  def index
    @title = 'Workshops'

    @editable_block_name = 'Workshops (Members Face)'
    @url = :admin_workshops

    @q = Workshop.ransack(params[:q])
    @events = @q.result(distinct: true)
                .accessible_by(current_ability)
                .paginate(page: params[:page], per_page: 15)

    respond_to do |format|
      format.html { render 'admin/events/index' }
      format.json { render json: @events }
    end
  end

  def show
    @title = @workshop.name
  end

  def new
    # Title is set by the view
  end

  def create
    respond_to do |format|
      if @workshop.save
        format.html { redirect_to admin_workshop_url(@workshop), notice: 'Workshop was successfully created.' }
      else
        format.html { render 'new', status: :unprocessable_entity }
      end
    end
  end

  def edit
    # Title is set by the view
  end

  def update
    respond_to do |format|
      if @workshop.update(workshop_params)
        format.html { redirect_to admin_workshop_url(@workshop), notice: 'Workshop was successfully updated.' }
      else
        format.html { render 'edit', status: :unprocessable_entity }
      end
    end
  end

  def destroy
    helpers.destroy_with_flash_message(@workshop)

    respond_to do |format|
      format.html { redirect_to admin_workshops_url }
      format.json { head :no_content }
    end
  end

  private

  def workshop_params
    params.require(:workshop).permit(:description, :name, :slug, :tagline, :author, :venue, :venue_id, :season,
                                     :season_id, :xts_id, :is_public, :image, :start_date, :end_date, :price,
                                     :spark_seat_slug, :proposal, :proposal_id,
                                     pictures_attributes: [:id, :_destroy, :description, :image],
                                     team_members_attributes: [:id, :_destroy, :position, :user, :user_id, :proposal])
  end
end
