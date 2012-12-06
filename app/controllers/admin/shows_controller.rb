class Admin::ShowsController < AdminController

  load_and_authorize_resource :find_by => :slug

  def index
    @title = "Shows"
    @shows = Show.all
  end

  def show
    @show = Show.find_by_slug(params[:id])
    @title = @show.name
  end

  def new
    @show = Show.new
    @users = User.all
    @title = "New Show"
  end

  def create
    @show = Show.new(params[:show])
    @users = User.all

    respond_to do |format|
      if @show.save
        format.html {redirect_to admin_show_url(@show), notice: 'Show was successfully created.'}
      else
        format.html {render "new"}
      end
    end
  end

  def edit
    @show = Show.find_by_slug(params[:id])
    @users = User.all
    @title = "Editing #{@show.name}"
  end

  def update
    @show = Show.find_by_slug(params[:id])
    @users = User.all

    respond_to do |format|
      if @show.update_attributes(params[:show])
        format.html { redirect_to admin_show_url(@show), notice: 'Show was successfully updated.' }
      else
        format.html { render "edit" }
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

  def create_questionnaire
    @show = Show.find_by_slug(params[:id])
    @show.create_questionnaire

    respond_to do |format|
      format.html { redirect_to admin_show_url(@show), notice: 'Questionnaire will be created.' }
      format.html { render :no_content }
    end
  end
end
