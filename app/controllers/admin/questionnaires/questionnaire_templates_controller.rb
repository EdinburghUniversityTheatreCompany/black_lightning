##
# Controller for Admin::Questionnaires::QuestionnaireTemplate
##
class Admin::Questionnaires::QuestionnaireTemplatesController < AdminController
  load_and_authorize_resource class: Admin::Questionnaires::QuestionnaireTemplate

  ##
  # GET /admin/questionnaires/questionnaire_templates
  #
  # GET /admin/questionnaires/questionnaire_templates.json
  ##
  def index
    @templates = Admin::Questionnaires::QuestionnaireTemplate.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @templates }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaire_templates/1
  #
  # GET /admin/questionnaires/questionnaire_templates/1.json
  ##
  def show
    @template = Admin::Questionnaires::QuestionnaireTemplate.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @template.to_json(include: { questions: {} }) }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaire_templates/new
  #
  # GET /admin/questionnaires/questionnaire_templates/new.json
  ##
  def new
    @template = Admin::Questionnaires::QuestionnaireTemplate.new

    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @template }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaire_templates/1/edit
  ##
  def edit
    @template = Admin::Questionnaires::QuestionnaireTemplate.find(params[:id])
  end

  ##
  # POST /admin/questionnaires/questionnaire_templates
  #
  # POST /admin/questionnaires/questionnaire_templates.json
  ##
  def create
    @template = Admin::Questionnaires::QuestionnaireTemplate.new(questionnaire_params)

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
  # PUT /admin/questionnaires/questionnaire_templates/1
  #
  # PUT /admin/questionnaires/questionnaire_templates/1.json
  ##
  def update
    @template = Admin::Questionnaires::QuestionnaireTemplate.find(params[:id])

    respond_to do |format|
      if @template.update_attributes(questionnaire_params)
        format.html { redirect_to @template, notice: 'Call question template was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit' }
        format.json { render json: @template.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/questionnaires/questionnaire_templates/1
  #
  # DELETE /admin/questionnaires/questionnaire_templates/1.json
  ##
  def destroy
    @template = Admin::Questionnaires::QuestionnaireTemplate.find(params[:id])
    @template.destroy

    respond_to do |format|
      format.html { redirect_to admin_questionnaires_questionnaire_templates_url }
      format.json { head :no_content }
    end
  end

  def questionnaire_params
    #TODO confirm this still works and isnt a testing framework quirk
    params.require(:template).permit(:name,
                                     questions_attributes: [:id, :_destroy, :question_text, :response_type])
  end
end
