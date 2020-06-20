##
# Controller for Admin::Questionnaires::Questionnaire
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

    @show_current_term_only = q.nil?

    # Set the range to the current term by default.
    @q.event_end_date_gt = helpers.start_of_term if @show_current_term_only
    @q.event_start_date_lt = helpers.end_of_term if @show_current_term_only

    # Is this a bit hacky? Yes. Does it work? Yes. Does it work when you try to do it the normal way? No. Can I try to fix it? Of course!
    # I suspect the generated SQL query gets messed up when you try to do:
    # @q.result.accessible_by(current_ability)
    # For some reason, it does work when you're an admin. Probably because accessible_by doesn't do anything in that case.

    result_ids = @q.result.ids

    @questionnaires = Admin::Questionnaires::Questionnaire.where(id: result_ids)
                                                          .accessible_by(current_ability)
                                                          .includes(:event)
                                                          .order('id DESC')
                                                          .group_by { |questionnaire| questionnaire.event.name }

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
    @title = "#{@questionnaire.name} for #{@questionnaire.event.name}"

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
      if @events_collection.empty?
        failure_notice = 'There are no future events, so it is not possible to add a questionnaire at the moment.'.freeze

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
    # The title is set in the view.

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
    params.require(:admin_questionnaires_questionnaire).permit(:event_id, :name,
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
    @event = Event.where(id: params[:event_id]).first
    events = Event.future.to_a
    events += [@event] unless @event.nil?
    @events_collection = events.collect { |event| [event.name, event.id] }
  end
end
