##
# Controller for Admin::Feedback. More details can be found there.
##

class Admin::FeedbacksController < AdminController
  include GenericController
  load_and_authorize_resource

  # GET /admin/feedbacks
  # GET /admin/feedbacks.json
  def index
    @show = Show.find_by_slug(params[:show_id])

    @title = "Feedback for #{@show.name}"

    # Sets index_query_params
    super
  end

  # GET /admin/feedbacks/new
  # GET /admin/feedbacks/new.json
  def new
    @show = Show.find_by_slug(params[:show_id])
    @title = "New Feedback for #{@show.name}"

    super
  end

  # GET /admin/feedbacks/1/edit
  def edit
    @show = @feedback.show
    @title = "Feedback with ID #{@feedback.id} for #{@show.name}"

    super
  end

  # POST /admin/feedbacks
  # POST /admin/feedbacks.json
  def create
    @show = Show.find_by_slug(params[:show_id])

    @feedback.show = @show

    respond_to do |format|
      if @feedback.save
        format.html do
          flash[:success] = "Feedback was successfully submitted."

          if can? :show, @feedback
            redirect_to admin_show_feedbacks_path(@show)
          else
            redirect_to admin_show_path(@show)
          end
        end
        # format.json { render json: @feedback, status: :created, location: @feedback }
      else
        format.html { render "new", status: :unprocessable_entity }
        # format.json { render json: @feedback.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /admin/feedbacks/1
  # PUT /admin/feedbacks/1.json
  def update
    @show = @feedback.show

    super
  end

  # DELETE /admin/feedbacks/1
  # DELETE /admin/feedbacks/1.json
  def destroy
    @show = @feedback.show

    super
  end

  private

  def resource_class
    Admin::Feedback
  end

  def permitted_params
    [ :body, :show, :show_id ]
  end

  def index_query_params
    { show_id: @show.id }
  end

  def update_redirect_url
    admin_show_feedbacks_path(@show)
  end

  def successful_destroy_redirect_url
    update_redirect_url
  end

  def new_title
    "Submit feedback for #{@show.name}"
  end

  def edit_title
    "Edit feedback for #{@show.name}"
  end
end
