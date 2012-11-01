class Admin::StaffingsController < AdminController
  
  load_and_authorize_resource :class => Admin::Staffing, :except => [:sign_up, :show_sign_up]
  
  # GET /admin/staffings
  # GET /admin/staffings.json
  def index
    @admin_staffings = Admin::Staffing.all
    @admin_staffings = @admin_staffings.group_by { |s| s.show_title }

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_staffings }
    end
  end

  # GET /admin/staffings/1
  # GET /admin/staffings/1.json
  def show
    @admin_staffing = Admin::Staffing.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_staffing }
    end
  end

  # GET /admin/staffings/new
  # GET /admin/staffings/new.json
  def new
    @users = User.accessible_by(current_ability, :manage) 
    @admin_staffing = Admin::Staffing.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @admin_staffing }
    end
  end

  # GET /admin/staffings/1/edit
  def edit
    @users = User.accessible_by(current_ability, :manage) 
    @admin_staffing = Admin::Staffing.find(params[:id])
  end

  # POST /admin/staffings
  # POST /admin/staffings.json
  def create
    @admin_staffing = Admin::Staffing.new(params[:admin_staffing])

    respond_to do |format|
      if @admin_staffing.save
        flash[:success] = 'Staffing was successfully created.'
        format.html { redirect_to edit_admin_staffing_path(@admin_staffing) }
        format.json { render json: @admin_staffing, status: :created, location: @admin_staffing }
      else
        format.html { render action: "new" }
        format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
      end
    end
  end
  
  def new_for_show
    @users = User.accessible_by(current_ability, :manage) 
    @admin_staffing = Admin::Staffing.new
  end
  
  def create_for_show
    admin_staffing = Admin::Staffing.new(params[:admin_staffing])
    admin_staffing_jobs = admin_staffing.staffing_jobs
    
    dates = params[:dates]
    
    dates.each_value do |date|
      staffing = admin_staffing.dup
      
      staffing.date = DateTime.civil(date[:year].to_i, date[:month].to_i, date[:day].to_i, date[:hour].to_i, date[:minute].to_i)
      
      if not staffing.save
        redirect_to redirect_to admin_staffings_url, alert: 'There were errors creating the staffing.'
        return
      end
      
      admin_staffing_jobs.each do |staffing_job|
        new_staffing_job = staffing_job.dup
        new_staffing_job.staffing_id = staffing.id
        new_staffing_job.save
      end
    end
    
    flash[:success] = 'Staffing was successfully created.'
    redirect_to admin_staffings_url
  end
  
  # PUT /admin/staffings/1
  # PUT /admin/staffings/1.json
  def update
    @admin_staffing = Admin::Staffing.find(params[:id])

    respond_to do |format|
      if @admin_staffing.update_attributes(params[:admin_staffing])
        flash[:success] = 'Staffing was successfully updated.'
        format.html { redirect_to edit_admin_staffing_path(@admin_staffing) }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
      end
    end
  end

  def show_sign_up
    authorize! :sign_up_for, Admin::StaffingJob
    @admin_staffing = Admin::Staffing.find(params[:id])
  end
  
  def sign_up
    authorize! :sign_up_for, Admin::StaffingJob
    @job = Admin::StaffingJob.find(params[:job_id])

    @job.user = current_user

    respond_to do |format|
      if current_user.phone_number == nil # you MUST have a phone number in your profile to be able to sign up for staffing
        format.html { redirect_to edit_admin_user_path(current_user), alert: "In order to sign up for staffing you need to provide a MOBILE phone number. We will text you to remind you about your staffing automatically, but we need to be able to get in touch if necessary." }
        format.json { head :no_content}
      elsif @job.save
        flash[:success] =  "Thank you for choosing to staff #{@job.staffing.show_title} - #{@job.name}, on #{(l @job.staffing.date, :format => :short)}."
        format.html { redirect_to admin_staffings_path }
        format.json { head :no_content }
      else
        format.html
        format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
      end
    end
  end



  # DELETE /admin/staffings/1
  # DELETE /admin/staffings/1.json
  def destroy
    @admin_staffing = Admin::Staffing.find(params[:id])
    @admin_staffing.destroy

    respond_to do |format|
      format.html { redirect_to admin_staffings_url }
      format.json { head :no_content }
    end
  end
end
