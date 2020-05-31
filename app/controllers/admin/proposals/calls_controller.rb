##
# Controller for Admin::Propsosals::Call. More details can be found there.
##

class Admin::Proposals::CallsController < AdminController
  before_action :set_paper_trail_whodunnit
  load_and_authorize_resource class: Admin::Proposals::Call

  ##
  # GET /admin/proposals/calls
  #
  # GET /admin/proposals/calls.json
  ##
  def index
    @title = 'Proposals to the EUTC'
    @calls = @calls.where(archived: [nil, false])

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @calls }
    end
  end

  ##
  # GET /admin/proposals/calls/1
  #
  # GET /admin/proposals/calls/1.json
  ##
  def show
    @title = @call.name

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @call }
    end
  end

  ##
  # GET /admin/proposals/calls/new
  #
  # GET /admin/proposals/calls/new.json
  ##
  def new
    # The title is set in the view.

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @call }
    end
  end

  ##
  # GET /admin/proposals/calls/1/edit
  ##
  def edit
    # The title is set in the view.
  end

  ##
  # POST /admin/proposals/calls
  #
  # POST /admin/proposals/calls.json
  ##
  def create
    respond_to do |format|
      if @call.save
        format.html { redirect_to @call, notice: 'Call was successfully created.' }
        format.json { render json: @call, status: :created, location: @call }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @call.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/proposals/calls/1
  #
  # PUT /admin/proposals/calls/1.json
  ##
  def update
    respond_to do |format|
      if @call.update(call_params)
        format.html { redirect_to @call, notice: 'Call was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @call.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/proposals/calls/1
  #
  # DELETE /admin/proposals/calls/1.json
  ##
  def destroy
    # TEST THE ADDITIONAL CONDITIOn
    helpers.destroy_with_flash_message(@call, additional_condition: @call.proposals.empty?)

    respond_to do |format|
      format.html { redirect_to admin_proposals_calls_path }
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/proposals/call/1/archive
  ##
  def archive
    if @call.archive
      flash[:success] = 'The Proposal Call has been successfully archived.'
    else
      flash[:error] = 'Error archiving the Proposal Call. Has the editing deadline been reached?'
    end

    respond_to do |format|
      format.html { redirect_to admin_proposals_calls_path }
      format.json { head :no_content }
    end
  end

  private

  def call_params
    params.require(:admin_proposals_call).permit(:submission_deadline, :editing_deadline, :name, :archived,
                                                 questions_attributes: [:id, :_destroy, :question_text, :response_type])
  end
end
