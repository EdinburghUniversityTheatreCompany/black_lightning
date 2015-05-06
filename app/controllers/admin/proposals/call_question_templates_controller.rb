##
# Controller for Admin::Proposals::CallQuestionTemplate. More details can be found there.
##

class Admin::Proposals::CallQuestionTemplatesController < AdminController
  load_and_authorize_resource class: Admin::Proposals::CallQuestionTemplate

  ##
  # GET /admin/proposals/call_question_templates
  #
  # GET /admin/proposals/call_question_templates.json
  ##
  def index
    @templates = Admin::Proposals::CallQuestionTemplate.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @templates }
    end
  end

  def show
    @template = Admin::Proposals::CallQuestionTemplate.find(params[:id])

    respond_to do |format|
      format.json { render json: @template.to_json(include: { questions: {} }) }
    end
  end

  ##
  # GET /admin/proposals/call_question_templates/new
  #
  # GET /admin/proposals/call_question_templates/new.json
  ##
  def new
    @template = Admin::Proposals::CallQuestionTemplate.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @template }
    end
  end

  ##
  # GET /admin/proposals/call_question_templates/1/edit
  ##
  def edit
    @template = Admin::Proposals::CallQuestionTemplate.find(params[:id])
  end

  ##
  # POST /admin/proposals/call_question_templates
  #
  # POST /admin/proposals/call_question_templates.json
  ##
  def create
    @template = Admin::Proposals::CallQuestionTemplate.new(params[:admin_proposals_call_question_template])

    respond_to do |format|
      if @template.save
        format.html { redirect_to @template, notice: 'Call question template was successfully created.' }
        format.json { render json: @template, status: :created, location: @template }
      else
        format.html { render 'new' }
        format.json { render json: @template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/proposals/call_question_templates/1
  #
  # PUT /admin/proposals/call_question_templates/1.json
  ##
  def update
    @template = Admin::Proposals::CallQuestionTemplate.find(params[:id])

    respond_to do |format|
      if @template.update_attributes(params[:admin_proposals_call_question_template])
        format.html { redirect_to @template, notice: 'Call question template was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit' }
        format.json { render json: @template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/proposals/call_question_templates/1
  #
  # DELETE /admin/proposals/call_question_templates/1.json
  ##
  def destroy
    @template = Admin::Proposals::CallQuestionTemplate.find(params[:id])
    @template.destroy

    respond_to do |format|
      format.html { redirect_to admin_proposals_call_question_templates_url }
      format.json { head :no_content }
    end
  end
end
