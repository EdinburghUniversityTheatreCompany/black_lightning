class Admin::Questionnaires::QuestionnairesController < AdminController

  load_and_authorize_resource :class => Admin::Questionnaires::Questionnaire

  # GET /admin/questionnaires/questionnaires
  # GET /admin/questionnaires/questionnaires.json
  def index
    @admin_questionnaires_questionnaires = Admin::Questionnaires::Questionnaire.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_questionnaires_questionnaires }
    end
  end

  # GET /admin/questionnaires/questionnaires/1
  # GET /admin/questionnaires/questionnaires/1.json
  def show
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_questionnaires_questionnaire }
    end
  end

  # GET /admin/questionnaires/questionnaires/1/edit
  def edit
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])
  end

  # POST /admin/questionnaires/questionnaires
  # POST /admin/questionnaires/questionnaires.json
  def create
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.new(params[:admin_questionnaires_questionnaire])

    respond_to do |format|
      if @admin_questionnaires_questionnaire.save
        format.html { redirect_to @admin_questionnaires_questionnaire, notice: 'Questionnaire was successfully created.' }
        format.json { render json: @admin_questionnaires_questionnaire, status: :created, location: @admin_questionnaires_questionnaire }
      else
        format.html { render "new" }
        format.json { render json: @admin_questionnaires_questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /admin/questionnaires/questionnaires/1
  # PUT /admin/questionnaires/questionnaires/1.json
  def update
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])

    respond_to do |format|
      if @admin_questionnaires_questionnaire.update_attributes(params[:admin_questionnaires_questionnaire])
        format.html { redirect_to @admin_questionnaires_questionnaire, notice: 'Questionnaire was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render "edit" }
        format.json { render json: @admin_questionnaires_questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /admin/questionnaires/questionnaires/1
  # DELETE /admin/questionnaires/questionnaires/1.json
  def destroy
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])
    @admin_questionnaires_questionnaire.destroy

    respond_to do |format|
      format.html { redirect_to admin_questionnaires_questionnaires_url }
      format.json { head :no_content }
    end
  end

  def answer
    @questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])

    @questionnaire.questions.each do |question|
      if question.answers.where(:answerable_id => @questionnaire.id, :answerable_type => "Admin::Questionnaires::Questionnaire").count == 0 then
        answer = Admin::Answer.new
        answer.question = question
        @questionnaire.answers.push(answer)
      end
    end

    respond_to do |format|
      format.html # answer.html.erb
      format.json { render json: @admin_questionnaires_questionnaire }
    end
  end
end
