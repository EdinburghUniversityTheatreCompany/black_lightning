class Admin::WorkshopsController < AdminController

  load_and_authorize_resource :find_by => :slug

  def index
    @title = "Workshops"
    @workshops = Workshop.all
  end

  def show
    @workshop = Workshop.find_by_slug(params[:id])
    @title = @workshop.name
  end

  def new
    @workshop = Workshop.new
    @users = User.by_first_name.all
    @title = "New Workshop"
  end

  def create
    @workshop = Workshop.new(params[:workshop])
    @users = User.by_first_name.all

    respond_to do |format|
      if @workshop.save
        format.html {redirect_to admin_workshop_url(@workshop), notice: 'Workshop was successfully created.'}
      else
        format.html {render "new"}
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
      if @workshop.update_attributes(params[:workshop])
        format.html { redirect_to admin_workshop_url(@workshop), notice: 'Workshop was successfully updated.' }
      else
        format.html { render "edit" }
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

end
