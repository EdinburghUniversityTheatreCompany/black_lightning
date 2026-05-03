##
# Controller for Admin::Staffing. More details can be found there.
##
class Admin::StaffingsController < AdminController
  include GenericController

  # Those are skipped because their permission depends on :sign_up_for staffing.
  # This is checked in the action.
  load_and_authorize_resource except: %i[sign_up sign_up_confirm]

  skip_load_resource only: %i[create]

  before_action :provision_calendar_token, only: [ :index ]

  ##
  # GET /admin/staffings
  #
  # GET /admin/staffings.json
  ##
  def index
    @title = "Staffing"

    @q = @staffings.ransack(params[:q])
    filtered = @q.result

    @upcoming_staffings = filtered.includes(:staffing_jobs, staffing_jobs: :user)
                                  .future.order(start_time: :asc).group_by(&:slug)

    # Paginate archived staffings by slug group (one row per show).
    # First, get paginated slugs ordered by most recent end_time.
    archived_slugs = filtered.past
                             .select("slug, MAX(end_time) as max_end_time")
                             .group(:slug)
                             .reorder("max_end_time DESC")
                             .page(params[:page]).per(10)

    # Then load the full staffing records for those slugs with eager loading.
    @archived_staffings = filtered.past
                                  .includes(:staffing_jobs, staffing_jobs: :user)
                                  .where(slug: archived_slugs.map(&:slug))
                                  .order(start_time: :asc)
                                  .group_by(&:slug)

    # Keep the pagination object for the view.
    @archived_staffings_pagination = archived_slugs

    respond_to do |format|
      format.html # index.html.erb
      format.turbo_stream
      # format.json { render json: @staffings }
    end
  end

  ##
  # GET /admin/staffings/:slug/grid
  ##
  def grid
    @staffings = @staffings.includes(:staffing_jobs, staffing_jobs: :user).where(slug: params[:slug])

    @can_sign_up = helpers.check_if_current_user_can_sign_up(current_user)

    @title = "Staffing for #{@staffings.empty? ? 'Nothing' : @staffings.first.show_title}"

    # Fall-back to past when future is empty, and to future when past is empty.
    if (params[:archived] == "true" && @staffings.past.any?) || @staffings.future.empty?
      @staffings = @staffings.past
    else
      @staffings = @staffings.future
    end

    @job_titles = @staffings.joins(:staffing_jobs).pluck("admin_staffing_jobs.name").uniq.sort

    @staffings_hash = @staffings.collect do |staffing|
      jobs = staffing.staffing_jobs.map { |job| [ job.name, job ] }.to_h

      staffing_hash = {
        staffing: staffing,
        start_time: staffing.start_time,
        end_time: staffing.end_time,
        jobs: jobs
      }

      next staffing_hash
    end

    respond_to do |format|
      format.html # index.html.erb
      # format.json { render json: @staffings_hash }
    end
  end

  ##
  # GET /admin/staffings/1
  #
  # GET /admin/staffings/1.json
  ##
  def show
    @title = "Staffing for #{@staffing.show_title}"

    @can_sign_up = helpers.check_if_current_user_can_sign_up(current_user)

    super
  end

  ##
  # Renders a page for creating a set of staffings with given dates.
  # ---
  # GET /admin/staffings/new
  ##
  def new
    @staffing = Admin::Staffing.new(counts_towards_debt: true)
    set_new_params

    super
  end

  ##
  # Creates staffings for the given dates.
  # ---
  # POST /admin/staffings/create
  ##
  def create
    # Has to be called @staffing in case it is passed to the 'new' form again.
    @staffing = Admin::Staffing.new(creation_params)

    start_times = params[:start_times]
    end_times = params[:end_times]

    slug = ""

    if start_times.nil? || end_times.nil?
      helpers.append_to_flash(:error, "You have not specified any start and end times.")
      failure = true
    end

    if @staffing.staffing_jobs.empty?
      helpers.append_to_flash(:error, "You have not added any jobs.")
      failure = true
    end

    unless @staffing.valid?(:pre_mass_create)
      @staffing.errors.full_messages.each { |error_message| helpers.append_to_flash(:error, error_message) }
      failure = true
    end

    first_pass = true
    unless failure
      start_times.values.zip(end_times.values).each do |start_time, end_time|
        staffing = @staffing.dup

        # Assumes that a staffing is shorter than 24 hours. This means that if end_time > start_time, it assumes it ends on the same day.
        # If end_time < start_time, it ends the next day.

        staffing.start_time = start_time
        staffing.end_time = end_time

        unless staffing.save
          failure = true

          message = first_pass ? "There is an issue with the form." : "There was an issue saving one of the staffings, and not all staffings have been saved."

          helpers.append_to_flash(:error, message)

          # Just to be sure, because the usual date time field does not exist in this form.
          staffing.errors.full_messages.each { |error_message| helpers.append_to_flash(:error, error_message) }

          break
        end

        slug = staffing.slug

        staffing.staffing_jobs << @staffing.staffing_jobs.collect(&:dup)

        first_pass = false
      end
    end

    respond_to do |format|
      if failure
        set_new_params
        format.html { render "new", status: :unprocessable_entity }
        # format.json { render json: @staffing.errors, status: :unprocessable_entity }
      else
        flash[:success] = "Staffing was successfully created."
        format.html { redirect_to grid_admin_staffings_path(slug) }
        # format.json { render status: :created }
      end
    end
  end

  # Edit is handled by the generic controller

  ##
  # PUT /admin/staffings/1
  #
  # PUT /admin/staffings/1.json
  ##
  def update
    @staffing.assign_attributes(update_params)

    respond_to do |format|
      if @staffing.save
        flash[:success] = "Staffing was successfully updated."
        format.html { redirect_to admin_staffing_path(@staffing) }
        # format.json { head :no_content }
      else
        format.html { render "edit", status: :unprocessable_entity }
        # format.json { render json: @staffing.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # A confirmation page to be displayed if JavaScript confirmation and PUT fails.
  # ---
  # PUT /admin/staffings/job/1/sign_up
  # GET /admin/staffings/job/1/sign_up
  ##
  def sign_up_confirm
    @job = Admin::StaffingJob.find(params[:id])

    @title = "Confirm staffing as #{@job.name} for #{@job.staffable.show_title}"

    @can_sign_up = helpers.check_if_current_user_can_sign_up(current_user)

    respond_to do |format|
      if helpers.check_if_current_user_can_sign_up(current_user, @job.name)
        format.html # render sign_up_confirm.html.erb
      else
        helpers.append_to_flash(:error, "There was an error signing up. Please contact the Front of House Manager") if flash[:error].blank?

        format.html { redirect_to admin_staffing_path(@job.staffable) }
        # format.json { render json: @job.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # Signs up the current user for the Admin::StaffingJob
  # ---
  # PUT /admin/staffings/1/sign_up
  ##
  def sign_up
    @job = Admin::StaffingJob.find(params[:id])

    if @job.user.nil? || @job.user == current_user
      @job.user = current_user
    else
      helpers.append_to_flash(:error, "Someone else has already signed up for this slot")
    end

    if @job.staffable.start_time < Time.current
      helpers.append_to_flash(:error, "You cannot sign up for staffings in the past. Please contact the Front of House-manager if you have staffed this shift.")
    end

    respond_to do |format|
      if helpers.check_if_current_user_can_sign_up(current_user, @job.name) && flash[:error].blank? && @job.save
        helpers.append_to_flash(:success, "Thank you for choosing to staff #{@job.staffable.show_title} - #{@job.name} on #{(l @job.staffable.start_time, format: :short)}.")

        format.html { redirect_to admin_staffing_path(@job.staffable) }
        format.turbo_stream
      else
        helpers.append_to_flash(:error, "There was an error signing up. Please contact the Front of House Manager") if flash[:error].blank?

        format.html { redirect_to admin_staffing_path(@job.staffable) }
        format.turbo_stream
      end
    end
  end

  ##
  # DELETE /admin/staffings/1
  #
  # DELETE /admin/staffings/1.json
  ##
  # Destroy is handled by the generic controller.

  private

  def set_new_params
    @shows = Show.future.pluck(:name)

    now = Time.current
    @default_start_time = Time.new(now.year, now.month, now.day, 18, 30, 0)
    @default_end_time = Time.new(now.year, now.month, now.day, 22, 00, 0)
  end

  def provision_calendar_token
    current_user.ensure_calendar_token!
  end

  def creation_params
    params.require(:admin_staffing).permit(:show_title, :counts_towards_debt,
                                           staffing_jobs_attributes: [ :id, :_destroy, :name, :user, :user_id ])
  end

  def update_params
    params.require(:admin_staffing).permit(:show_title, :start_time, :end_time, :counts_towards_debt,
                                            staffing_jobs_attributes: [ :id, :_destroy, :name, :user, :user_id ])
  end

  def edit_title
    "Edit Staffing for #{@staffing.show_title}"
  end
end
