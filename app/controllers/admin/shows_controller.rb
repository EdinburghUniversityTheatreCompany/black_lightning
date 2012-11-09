class Admin::ShowsController < AdminController

  load_and_authorize_resource :find_by => :slug

  def index
    @shows = Show.all
  end

  def show
    @show = Show.find_by_slug(params[:id])
  end

  def new
    @show = Show.new
    @users = User.all
  end

  def create
    @show = Show.new(params[:show])
    @users = User.all

    respond_to do |format|
      if @show.save
        format.html {redirect_to admin_show_url(@show), notice: 'Show was successfully created.'}
      else
        format.html {render action: "new"}
      end
    end
  end

  def edit
    @show = Show.find_by_slug(params[:id])
    @users = User.all
  end

  def update
    @show = Show.find_by_slug(params[:id])
    @users = User.all

    respond_to do |format|
      if @show.update_attributes(params[:show])
        format.html { redirect_to admin_show_url(@show), notice: 'Show was successfully updated.' }
      else
        format.html { render action: "edit" }
      end
    end
  end

  def destroy
    @show = Show.find_by_slug(params[:id])
    @show.destroy

    respond_to do |format|
      format.html { redirect_to admin_shows_url }
      format.json { head :no_content }
    end
  end
end
