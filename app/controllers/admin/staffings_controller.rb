##
# Controller for Admin::Staffing. More details can be found there.
##
class Admin::StaffingsController < AdminController
  skip_before_filter :authorize_backend!
  load_and_authorize_resource class: Admin::Staffing, except: [:sign_up, :sign_up_confirm]

  ##
  # Helper methods
  ##

  def check_if_current_user_can_sign_up 
    return (can? :sign_up_for, Admin::StaffingJob) && !current_user.phone_number.blank?
  end
  ##
  # GET /admin/staffings
  #
  # GET /admin/staffings.json
  ##
  def index
    @admin_staffings = Admin::Staffing.future.group_by(&:slug)
    @admin_staffings_archive = Admin::Staffing.past.group_by(&:slug)

    @title = 'Staffing'
    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_staffings }
    end
  end

  ##
  # GET /admin/staffings/:slug/grid
  ##
  def grid
    authorize! :sign_up_for, Admin::StaffingJob
    @can_sign_up = check_if_current_user_can_sign_up

    if params[:archived] == 'true'
      @staffings = Admin::Staffing.past.where(slug: params[:slug])
    else
      @staffings = Admin::Staffing.future.where(slug: params[:slug])
    end

    @title = "Staffing for #{@staffings.empty? ? "Nothing" : @staffings.first.show_title}"

    @job_titles = @staffings.joins(:staffing_jobs).select('admin_staffing_jobs.name').uniq.collect(&:name).sort

    @staffings = @staffings.includes(staffing_jobs: :user)
    @staffings_hash = @staffings.all.collect do |s|
      staffing_hash = {}
      staffing_hash[:staffing] = s
      staffing_hash[:start_time] = s.start_time
      staffing_hash[:end_time] = s.end_time
      staffing_hash[:jobs] = {}
      s.staffing_jobs.each do |j|
        staffing_hash[:jobs][j.name] = j
      end

      next staffing_hash
    end

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  ##
  # GET /admin/staffings/1
  #
  # GET /admin/staffings/1.json
  ##
  def show
    authorize! :sign_up_for, Admin::StaffingJob
    @can_sign_up = check_if_current_user_can_sign_up

    @admin_staffing = Admin::Staffing.find(params[:id])
    @title = "Staffing for #{@admin_staffing.show_title}"
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_staffing }
    end
  end

  ##
  # Renders a page for creating a set of staffings with given dates.
  # ---
  # GET /admin/staffings/new
  ##
  def new
    @users = User.all
    @admin_staffing = Admin::Staffing.new(counts_towards_debt: true)
    @title = 'New Staffing for Show'
    @is_new = true

    now = Time.now
    @default_start_time = Time.new(now.year, now.month, now.day, 18, 00, 0)
    @default_end_time = @default_start_time + 3.hours
  end

  ##
  # GET /admin/staffings/1/edit
  ##
  def edit
    @users = User.all
    @admin_staffing = Admin::Staffing.find(params[:id])
    @title = "Editing staffing for #{@admin_staffing.show_title}"
    @is_new = false
  end

  ##
  # POST /admin/staffings
  #
  # POST /admin/staffings.json
  ##
  def create
    @users = User.all
    @admin_staffing = Admin::Staffing.new(params[:admin_staffing])

    respond_to do |format|
      if @admin_staffing.save
        flash[:success] = 'Staffing was successfully created.'
        format.html { redirect_to admin_staffing_path(@admin_staffing) }
        format.json { render json: @admin_staffing, status: :created, location: @admin_staffing }
      else
        format.html { render 'new' }
        format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # Creates staffings for the given dates.
  # ---
  # PUT  /admin/staffings/create_for_show
  ##
  def create_for_show
    admin_staffing = Admin::Staffing.new(params[:admin_staffing])
    admin_staffing_jobs = admin_staffing.staffing_jobs

    start_times = params[:start_times]
    end_times = params[:end_times]

    begin
      start_times.values.zip(end_times.values).each do |start_time, end_time|
        staffing = admin_staffing.dup

        staffing.start_time = Time.zone.local(start_time[:year].to_i, start_time[:month].to_i, start_time[:day].to_i, start_time[:hour].to_i, start_time[:minute].to_i)
        staffing.end_time = Time.zone.local(start_time[:year].to_i, start_time[:month].to_i, start_time[:day].to_i, end_time[:hour].to_i, end_time[:minute].to_i) # right now I'm assuming staffings end on the same day as they begin. Makes the UI cleaner

        staffing.save!

        staffing.staffing_jobs << admin_staffing_jobs.collect(&:dup)
      end
    rescue => e
      redirect_to redirect_to admin_staffings_path, alert: 'There were errors creating the staffing.'
      return
    end

    flash[:success] = 'Staffing was successfully created.'
    redirect_to admin_staffings_path
  end

  ##
  # PUT /admin/staffings/1
  #
  # PUT /admin/staffings/1.json
  ##
  def update
    @admin_staffing = Admin::Staffing.find(params[:id])

    respond_to do |format|
      if @admin_staffing.update_attributes(params[:admin_staffing])
        flash[:success] = 'Staffing was successfully updated.'
        format.html { redirect_to admin_staffing_path(@admin_staffing) }
        format.json { head :no_content }
      else
        format.html { render 'edit' }
        format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # A confirmation page to be displayed if JavaScript confirmation and PUT fails.
  # ---
  # GET /admin/staffings/job/1/sign_up
  ##
  def sign_up_confirm
    authorize! :sign_up_for, Admin::StaffingJob
    @can_sign_up = check_if_current_user_can_sign_up

    return unless @can_sign_up

    @job = Admin::StaffingJob.find(params[:id])

    @title = 'Confirm Staffing'
  end

  ##
  # Signs up the current user for the Admin::StaffingJob
  # ---
  # PUT /admin/staffings/1/sign_up
  ##
  def sign_up
    authorize! :sign_up_for, Admin::StaffingJob

    @job = Admin::StaffingJob.find(params[:id])
    @job.user = current_user

    respond_to do |format|
      if current_user.phone_number.blank? # you MUST have a phone number in your profile to be able to sign up for staffing
        format.html { redirect_to edit_admin_user_path(current_user), alert: 'In order to sign up for staffing you need to provide a MOBILE phone number so we are able to get in touch if necessary.' }
        format.json { render json: {error: 'no_number '} }
      elsif @job.staffable.start_time > Time.now
        if @job.save
          format.html do
            flash[:success] = "Thank you for choosing to staff #{@job.staffable.show_title} - #{@job.name}, on #{(l @job.staffable.start_time, format: :short)}."
            redirect_to admin_staffings_path
          end
          format.json { render json: @job.to_json(include: {user: {}, staffable: {}}, methods: [:js_start_time, :js_end_time]) }
        else
          format.html
          format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
        end
      else
        format.html  do
          flash[:failure] = 'You can\'t sign up for staffings in the past. Please contact the FOH manager if you have staffed this shift.'
          redirect_to admin_staffings_path
        end
        format.json { render json: @admin_staffing.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/staffings/1
  #
  # DELETE /admin/staffings/1.json
  ##
  def destroy
    @admin_staffing = Admin::Staffing.find(params[:id])
    @admin_staffing.destroy

    respond_to do |format|
      format.html { redirect_to admin_staffings_url }
      format.json { head :no_content }
    end
  end
end
