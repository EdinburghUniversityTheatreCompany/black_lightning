class Admin::SeasonsController < AdminController
  load_and_authorize_resource find_by: :slug
  skip_load_resource only: %i[index]

  # GET /admin/seasons
  # GET /admin/seasons.json
  def index
    @title = 'Seasons'

    @editable_block_name = 'Seasons (Members Face)'
    @url = :admin_seasons

    @q = Season.ransack(params[:q])
    @events = @q.result(distinct: true)
                .accessible_by(current_ability)
                .paginate(page: params[:page], per_page: 15)

    respond_to do |format|
      format.html { render 'admin/events/index' }
      format.json { render json: @events }
    end
  end

  # GET /admin/seasons/1
  # GET /admin/seasons/1.json
  def show
    @title = @season.name

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @season }
    end
  end

  # GET /admin/seasons/new
  # GET /admin/seasons/new.json
  def new
    @title = 'New Season'

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @season }
    end
  end

  # GET /admin/seasons/1/edit
  def edit
    @title = "Editing #{@season.name}"

    respond_to do |format|
      format.html # edit.html.erb
      format.json { render json: @season }
    end
  end

  # POST /admin/seasons
  # POST /admin/seasons.json
  def create
    respond_to do |format|
      if @season.save
        format.html { redirect_to admin_season_path(@season), notice: "Season #{@season.name} was successfully created." }
        format.json { render json: @season, status: :created, location: @season }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @season.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /admin/seasons/1
  # PUT /admin/seasons/1.json
  def update
    respond_to do |format|
      if @season.update(season_params)
        format.html { redirect_to admin_season_path(@season), notice: "Season #{@season.name} was successfully updated." }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @season.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/seasons/1
  # DELETE /admin/seasons/1.json
  def destroy
    helpers.destroy_with_flash_message(@season)

    respond_to do |format|
      format.html { redirect_to admin_seasons_url }
      format.json { head :no_content }
    end
  end

  private

  def season_params
    params.require(:season).permit(:name, :tagline, :slug, :description, :start_date, :end_date, :image,
      :venue_id, :is_public, :author, :price,
      pictures_attributes: [:id, :_destroy, :description, :image],
      team_members_attributes: [:id, :_destroy, :position, :user, :user_id, :proposal],
      event_ids: [])
  end
 end
