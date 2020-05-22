##
# Controller for Admin::Questionnaires::QuestionnaireTemplate
##
class Admin::Questionnaires::QuestionnaireTemplatesController < AdminController
  load_and_authorize_resource

  ##
  # GET /admin/questionnaires/questionnaire_templates
  #
  # GET /admin/questionnaires/questionnaire_templates.json
  ##
  def index
    @title = 'Questionnaire Templates'

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @questionnaire_templates }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaire_templates/1
  #
  # GET /admin/questionnaires/questionnaire_templates/1.json
  ##
  def show
    @title = "#{@questionnaire_template.name} Questionnaire Template"
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @questionnaire_template.to_json(include: { questions: {} }) }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaire_templates/new
  #
  # GET /admin/questionnaires/questionnaire_templates/new.json
  ##
  def new
    # The title is set by the view.

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @questionnaire_template }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaire_templates/1/edit
  ##
  def edit
    # The title is set by the view.
  end

  ##
  # POST /admin/questionnaires/questionnaire_templates
  #
  # POST /admin/questionnaires/questionnaire_templates.json
  ##
  def create
    respond_to do |format|
      if @questionnaire_template.save
        format.html { redirect_to @questionnaire_template, notice: "The questionnaire template #{@questionnaire_template.name} was successfully created." }
        format.json { render json: @questionnaire_template, status: :created, location: @questionnaire_template }
      else
        format.html { render 'new', status: :unprocessable_entity }
        format.json { render json: @questionnaire_template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT /admin/questionnaires/questionnaire_templates/1
  #
  # PUT /admin/questionnaires/questionnaire_templates/1.json
  ##
  def update
    respond_to do |format|
      if @questionnaire_template.update(questionnaire_template_params)
        format.html { redirect_to @questionnaire_template, notice: "The questionnaire template #{@questionnaire_template.name} was successfully updated." }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @questionnaire_template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/questionnaires/questionnaire_templates/1
  #
  # DELETE /admin/questionnaires/questionnaire_templates/1.json
  ##
  def destroy
    helpers.destroy_with_flash_message(@questionnaire_template)

    respond_to do |format|
      format.html { redirect_to admin_questionnaires_questionnaire_templates_url }
      format.json { head :no_content }
    end
  end

  def questionnaire_template_params
    params.require(:admin_questionnaires_questionnaire_template).permit(:name,
                                     questions_attributes: [:id, :_destroy, :question_text, :response_type])
  end
end
