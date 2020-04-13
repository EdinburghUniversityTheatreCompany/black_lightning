class Admin::SeasonsController < AdminController
  # load_and_authorize_resource

  # GET /admin/seasons
  # GET /admin/seasons.json
  def index
    @seasons = Season.all.order(:start_date)
    @title = 'Seasons'
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @seasons }
    end
  end

  # GET /admin/seasons/1
  # GET /admin/seasons/1.json
  def show
    @season = Season.find_by_slug(params[:id])

    @title = @season.name
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @season }
    end
  end

  # GET /admin/seasons/new
  # GET /admin/seasons/new.json
  def new
    @season = Season.new
    @users = User.by_first_name.all
    @title = 'New Season'
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @season }
    end
  end

  # GET /admin/seasons/1/edit
  def edit
    @season = Season.find_by_slug(params[:id])
    @users = User.by_first_name.all
    @title = "Editing #{@season.name}"
  end

  # POST /admin/seasons
  # POST /admin/seasons.json
  def create
    @season = Season.new(params[:season])
    @users = User.by_first_name.all

    @season.event_ids = params[:season][:event_ids]

    respond_to do |format|
      if @season.save
        format.html { redirect_to admin_season_path(@season), notice: "Season #{@season.name} was successfully created." }
        format.json { render json: @season, status: :created, location: @season }
      else
        format.html { render 'new' }
        format.json { render json: @season.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /admin/seasons/1
  # PUT /admin/seasons/1.json
  def update
    @season = Season.find_by_slug(params[:id])
    @users = User.by_first_name.all

    @season.event_ids = params[:season][:event_ids]

    respond_to do |format|
      if @season.update_attributes(params[:season])
        format.html { redirect_to admin_season_path(@season), notice: "Season #{@season.name} was successfully updated." }
        format.json { head :no_content }
      else
        format.html { render 'edit' }
        format.json { render json: @season.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/seasons/1
  # DELETE /admin/seasons/1.json
  def destroy
    @season = Season.find_by_slug(params[:id])
    @season.destroy

    respond_to do |format|
      format.html { redirect_to admin_seasons_url }
      format.json { head :no_content }
    end
  end
end
