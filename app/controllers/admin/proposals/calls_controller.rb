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
    @admin_proposals_calls = Admin::Proposals::Call.where(archived: [nil, false])

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_proposals_calls }
    end
  end

  ##
  # GET /admin/proposals/calls/1
  #
  # GET /admin/proposals/calls/1.json
  ##
  def show
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_proposals_call }
    end
  end

  ##
  # GET /admin/proposals/calls/new
  #
  # GET /admin/proposals/calls/new.json
  ##
  def new
    @admin_proposals_call = Admin::Proposals::Call.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @admin_proposals_call }
    end
  end

  ##
  # GET /admin/proposals/calls/1/edit
  ##
  def edit
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])
  end

  ##
  # POST /admin/proposals/calls
  #
  # POST /admin/proposals/calls.json
  ##
  def create
    @admin_proposals_call = Admin::Proposals::Call.new(call_params)

    respond_to do |format|
      if @admin_proposals_call.save
        format.html { redirect_to @admin_proposals_call, notice: 'Call was successfully created.' }
        format.json { render json: @admin_proposals_call, status: :created, location: @admin_proposals_call }
      else
        format.html { render 'new' }
        format.json { render json: @admin_proposals_call.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/proposals/calls/1
  #
  # PUT /admin/proposals/calls/1.json
  ##
  def update
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])

    respond_to do |format|
      if @admin_proposals_call.update_attributes(call_params)
        format.html { redirect_to @admin_proposals_call, notice: 'Call was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit' }
        format.json { render json: @admin_proposals_call.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/proposals/calls/1
  #
  # DELETE /admin/proposals/calls/1.json
  ##
  def destroy
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])
    @admin_proposals_call.destroy

    respond_to do |format|
      format.html { redirect_to admin_proposals_calls_url }
      format.json { head :no_content }
    end
  end

  ##
  # PUT /admin/proposals/call/1/archive
  ##
  def archive
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])
    @admin_proposals_call.archive

    respond_to do |format|
      format.html { redirect_to admin_proposals_calls_url }
      format.json { head :no_content }
    end
  end

  private
  def call_params
    params.require(:admin_proposals_call).permit(:deadline, :name, :open, :archived,
                                 questions_attributes: [:question_text, :response_type])
  end
end
