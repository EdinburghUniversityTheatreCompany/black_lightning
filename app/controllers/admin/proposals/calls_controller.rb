class Admin::Proposals::CallsController < AdminController
  # GET /admin/proposals/calls
  # GET /admin/proposals/calls.json
  def index
    @admin_proposals_calls = Admin::Proposals::Call.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_proposals_calls }
    end
  end

  # GET /admin/proposals/calls/1
  # GET /admin/proposals/calls/1.json
  def show
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_proposals_call }
    end
  end

  # GET /admin/proposals/calls/new
  # GET /admin/proposals/calls/new.json
  def new
    @admin_proposals_call = Admin::Proposals::Call.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @admin_proposals_call }
    end
  end

  # GET /admin/proposals/calls/1/edit
  def edit
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])
  end

  # POST /admin/proposals/calls
  # POST /admin/proposals/calls.json
  def create
    @admin_proposals_call = Admin::Proposals::Call.new(params[:admin_proposals_call])

    respond_to do |format|
      if @admin_proposals_call.save
        format.html { redirect_to @admin_proposals_call, notice: 'Call was successfully created.' }
        format.json { render json: @admin_proposals_call, status: :created, location: @admin_proposals_call }
      else
        format.html { render action: "new" }
        format.json { render json: @admin_proposals_call.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /admin/proposals/calls/1
  # PUT /admin/proposals/calls/1.json
  def update
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])

    respond_to do |format|
      if @admin_proposals_call.update_attributes(params[:admin_proposals_call])
        format.html { redirect_to @admin_proposals_call, notice: 'Call was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @admin_proposals_call.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/proposals/calls/1
  # DELETE /admin/proposals/calls/1.json
  def destroy
    @admin_proposals_call = Admin::Proposals::Call.find(params[:id])
    @admin_proposals_call.destroy

    respond_to do |format|
      format.html { redirect_to admin_proposals_calls_url }
      format.json { head :no_content }
    end
  end
end
