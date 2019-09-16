##
# Controller for Admin::Questionnaires::Questionnaire
# ---
# *IMPORTANT*
#
# Due to the complex nature of questionnaire permissions, each action may need to be authorized
# in the controller method using the authorize! method.
#
# Failure to correctly do so will cause bad things to happen (kittens may die).
##
class Admin::Questionnaires::QuestionnairesController < AdminController
  ##
  # GET /admin/questionnaires/questionnaires
  #
  # GET /admin/questionnaires/questionnaires.json
  ##
  def index
    if (current_user.has_role? :committee) || (current_user.has_role? :admin)
      @admin_questionnaires_questionnaires = Admin::Questionnaires::Questionnaire
    else
      @admin_questionnaires_questionnaires = Admin::Questionnaires::Questionnaire.joins(:users).where('user_id = ?', current_user.id)
    end

    @admin_questionnaires_questionnaires = @admin_questionnaires_questionnaires.order('id DESC').all.group_by(&:show)

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @admin_questionnaires_questionnaires }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaires/1
  #
  # GET /admin/questionnaires/questionnaires/1.json
  ##
  def show
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])

    authorize!(:read, @admin_questionnaires_questionnaire)

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @admin_questionnaires_questionnaire }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaires/1/edit
  ##
  def edit
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])

    authorize!(:edit, @admin_questionnaires_questionnaire)
  end

  ##
  # PUT /admin/questionnaires/questionnaires/1
  #
  # PUT /admin/questionnaires/questionnaires/1.json
  ##
  def update
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])

    # Try authorizing update first
    begin
      authorize!(:update, @admin_questionnaires_questionnaire)
    rescue CanCan::AccessDenied
      # Otherwise, try answer as well.
      authorize!(:answer, @admin_questionnaires_questionnaire)
    end

    respond_to do |format|
      if @admin_questionnaires_questionnaire.update_attributes(questionnaire_params)
        format.html { redirect_to @admin_questionnaires_questionnaire, notice: 'Questionnaire was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit' }
        format.json { render json: @admin_questionnaires_questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/questionnaires/questionnaires/1
  #
  # DELETE /admin/questionnaires/questionnaires/1.json
  ##
  def destroy
    @admin_questionnaires_questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])

    authorize!(:destroy, @admin_questionnaires_questionnaire)

    @admin_questionnaires_questionnaire.destroy

    respond_to do |format|
      format.html { redirect_to admin_questionnaires_questionnaires_url }
      format.json { head :no_content }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaire/1/answer
  ##
  def answer
    @questionnaire = Admin::Questionnaires::Questionnaire.find(params[:id])

    authorize!(:answer, @questionnaire)

    @questionnaire.questions.each do |question|
      if question.answers.where(answerable_id: @questionnaire.id, answerable_type: 'Admin::Questionnaires::Questionnaire').count == 0
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

  private
  def questionnaire_params
    #TODO check this prevents users from changing questions when answering them
    params.require(:admin_questionnaires_questionnaire).permit(:name,
                                                               questions: [:question_text, :response_type],
                                                               answers: [:answer, :question_id, :file])
  end
end
