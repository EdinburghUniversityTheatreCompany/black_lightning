##
# Admin controller for Venue management.
##
class Admin::VenuesController < AdminController
  load_and_authorize_resource

  ##
  # GET /venues
  #
  # GET /venues.json
  ##
  def index
    @title = 'Venues'

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @venues }
    end
  end

  ##
  # GET /venues/1
  #
  # GET /venues/1.json
  ##
  def show
    @title = @venue.name

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @venue }
    end
  end

  ##
  # GET /venues/new
  #
  # GET /venues/new.json
  ##
  def new
    # Title is set by the view.

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @venue }
    end
  end

  ##
  # GET /venues/1/edit
  ##
  def edit
    # Title is set by the view.
  end

  ##
  # POST /venues
  #
  # POST /venues.json
  ##
  def create
    respond_to do |format|
      if @venue.save
        format.html { redirect_to admin_venue_path(@venue), notice: 'Venue was successfully created.' }
        format.json { render json: @venue, status: :created, location: @venue }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @venue.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /venues/1
  #
  # PUT /venues/1.json
  ##
  def update
    respond_to do |format|
      if @venue.update(venue_params)
        format.html { redirect_to admin_venue_path(@venue), notice: 'Venue was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @venue.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /venues/1
  #
  # DELETE /venues/1.json
  ##
  def destroy
    helpers.destroy_with_flash_message(@venue)

    respond_to do |format|
      format.html { redirect_to admin_venues_url }
      format.json { head :no_content }
    end
  end

  private

  def venue_params
    params.require(:venue).permit(:description, :image, :location, :name, :tagline,
                                  pictures_attributes: %I[id _destroy description image])
  end
end
