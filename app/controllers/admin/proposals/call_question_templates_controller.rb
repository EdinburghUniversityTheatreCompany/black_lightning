##
# Controller for Admin::Proposals::CallQuestionTemplate. More details can be found there.
##

class Admin::Proposals::CallQuestionTemplatesController < AdminController
  load_and_authorize_resource

  ##
  # GET /admin/proposals/call_question_templates
  #
  # GET /admin/proposals/call_question_templates.json
  ##
  def index
    @title = 'Call Question Templates'

    @call_question_templates.includes(:questions)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @call_question_templates }
    end
  end

  ##
  # GET /admin/proposlas/call_question_templates/1
  #
  # GET /admin/proposlas/call_question_templates/1.json
  ##
  def show
    @title = @call_question_template.name

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @call_question_template.to_json(include: { questions: {} }) }
    end
  end

  ##
  # GET /admin/proposals/call_question_templates/new
  #
  # GET /admin/proposals/call_question_templates/new.json
  ##
  def new
    # The title is set by the view.

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @call_question_template }
    end
  end

  ##
  # POST /admin/proposals/call_question_templates
  #
  # POST /admin/proposals/call_question_templates.json
  ##
  def create
    respond_to do |format|
      if @call_question_template.save
        format.html { redirect_to @call_question_template, notice: 'Call question template was successfully created.' }
        format.json { render json: @call_question_template, status: :created, location: @call_question_template }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @call_question_template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # GET /admin/proposals/call_question_templates/1/edit
  ##
  def edit
    # The title is set by the view.
  end

  ##
  # PUT /admin/proposals/call_question_templates/1
  #
  # PUT /admin/proposals/call_question_templates/1.json
  ##
  def update
    respond_to do |format|
      if @call_question_template.update(call_question_template_params)
        format.html { redirect_to @call_question_template, notice: 'Call question template was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @call_question_template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/proposals/call_question_templates/1
  #
  # DELETE /admin/proposals/call_question_templates/1.json
  ##
  def destroy
    helpers.destroy_with_flash_message(@call_question_template)

    respond_to do |format|
      format.html { redirect_to admin_proposals_call_question_templates_url }
      format.json { head :no_content }
    end
  end

  private

  def call_question_template_params
    params.require(:admin_proposals_call_question_template).permit(:name,
                                                                   questions_attributes: %I[question_text response_type _destroy id])
  end
end
