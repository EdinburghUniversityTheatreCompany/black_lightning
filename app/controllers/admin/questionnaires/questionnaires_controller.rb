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
  load_and_authorize_resource
  ##
  # GET /admin/questionnaires/questionnaires
  #
  # GET /admin/questionnaires/questionnaires.json
  ##
  def index
    @title = 'Questionnaires'

    q = params[:q]

    @q = Admin::Questionnaires::Questionnaire.ransack(q)
    @q.show_end_date_gt = helpers.start_of_term unless q
    @q.show_start_date_lt = helpers.end_of_term unless q

    @questionnaires = @q.result.accessible_by(current_ability)

    @questionnaires = @questionnaires.includes(:show).order('id DESC').group_by { |questionnaire| questionnaire.show.name }

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @questionnaires }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaires/1
  #
  # GET /admin/questionnaires/questionnaires/1.json
  ##
  def show
    @title = "#{@questionnaire.name} for #{@questionnaire.show.name}"

    @questionnaire.instantiate_answers!

    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @questionnaire }
    end
  end

  ##
  # GET /admin/questionnaires/questionnaires/1/edit
  ##
  def edit
    # The title is set in the view.
  end

  ##
  # GET /admin/questionnaires/questionnaires/new/1
  ##
  def new
    # The title is set in the view.
    set_create_form_parameters

    respond_to do |format|
      if @shows_collection.empty?
        failure_notice = 'There are no future shows, so it is not possible to add a questionnaire at the moment.'.freeze

        format.html { redirect_to Admin::Questionnaires::Questionnaire, notice: failure_notice }
        format.json { render json: failure_notice }
      else
        format.html
        format.json { render json: @maintenance_debt }
      end
    end
  end

  ##
  # POST /admin/questionnaires/questionnaires/new/1
  #
  # POST /admin/questionnaires/questionnaires/new/1.json
  ##
  def create
    respond_to do |format|
      if @questionnaire.save
        format.html { redirect_to @questionnaire, notice: 'Questionnaire was successfully created.' }
        format.json { head :no_content }
      else
        format.html do
          set_create_form_parameters
          render 'new', status: :unprocessable_entity
        end
        format.json { render json: @questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # PUT/PATCH /admin/questionnaires/questionnaires/1
  #
  # PUT/PATCH /admin/questionnaires/questionnaires/1.json
  ##
  def update
    respond_to do |format|
      if @questionnaire.update(update_params)
        format.html { redirect_to @questionnaire, notice: 'Questionnaire was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render 'edit', status: :unprocessable_entity }
        format.json { render json: @questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # GET /admin/questionnaires/questionnaire/1/answer
  ##
  def answer
    @title = "Answering #{@questionnaire.name} for #{@questionnaire.show.name}"

    @questionnaire.instantiate_answers!

    respond_to do |format|
      format.html # answer.html.erb
      format.json { render json: @questionnaire }
    end
  end

  ##
  # PUT/PATCH /admin/questionnaires/questionnaire/1/answer
  #
  # PUT/PATCH /admin/questionnaires/questionnaire/1/answer.json
  ## 
  def set_answers
    respond_to do |format|
      if @questionnaire.update(answer_params)
        format.html { redirect_to @questionnaire, notice: 'The answers have been sucessfully submitted.' }
        format.json { head :no_content }
      else
        format.html { render 'answer', status: :unprocessable_entity }
        format.json { render json: @questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end

  ##
  # DELETE /admin/questionnaires/questionnaires/1
  #
  # DELETE /admin/questionnaires/questionnaires/1.json
  ##
  def destroy
    helpers.destroy_with_flash_message(@questionnaire)

    respond_to do |format|
      format.html { redirect_to admin_questionnaires_questionnaires_url }
      format.json { head :no_content }
    end
  end

  private

  def create_params
    params.require(:admin_questionnaires_questionnaire).permit(:show_id, :name,
      questions_attributes: [:id, :_destroy, :question_text, :response_type])
  end

  def update_params
    params.require(:admin_questionnaires_questionnaire).permit(:name,
      questions_attributes: [:id, :_destroy, :question_text, :response_type])
  end

  def answer_params
    params.require(:admin_questionnaires_questionnaire).permit(
      answers_attributes: [:id, :_destroy, :answer, :question_id, :file])
  end

  def set_create_form_parameters
    @show = Show.where(id: params[:show_id]).first
    shows = Show.future.to_a
    shows += [@show] unless @show.nil?
    @shows_collection = shows.collect { |show| [show.name, show.id] }
  end
end
