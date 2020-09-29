##
# Controller for Admin::Questionnaires::Questionnaire
##
class Admin::Questionnaires::QuestionnairesController < AdminController
  include GenericController

  load_and_authorize_resource

  # Index has an override for the index resources

  ##
  # GET /admin/questionnaires/questionnaires/1
  #
  # GET /admin/questionnaires/questionnaires/1.json
  ##
  def show
    @title = "#{@questionnaire.name} for #{@questionnaire&.event&.name}"

    @questionnaire.instantiate_answers!

    super
  end

  ##
  # GET /admin/questionnaires/questionnaires/new/1
  ##
  def new
    # The title is set in the view.
    set_create_form_parameters

    if @events_collection.empty?
      flash[:error] = 'There are no future events, so it is not possible to add a questionnaire at the moment.'

      respond_to do |format|
        format.html { redirect_to Admin::Questionnaires::Questionnaire }
        format.json { render json: flash[:error] }
      end
    else
      super
    end
  end

  ##
  # POST /admin/questionnaires/questionnaires/new/1
  #
  # POST /admin/questionnaires/questionnaires/new/1.json
  ##
  def create
    set_create_form_parameters

    super
  end

  # Edit and Update are handled by the Generic Controller.

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
        flash[:success] = 'The answers have been sucessfully submitted.'
        format.html { redirect_to @questionnaire }
        format.json { head :no_content }
      else
        format.html { render 'answer', status: :unprocessable_entity }
        format.json { render json: @questionnaire.errors, status: :unprocessable_entity }
      end
    end
  end

  # Destroy is handled by the Generic Controller.

  private

  def answer_params
    resource_params.permit(answers_attributes: [:id, :_destroy, :answer, :question_id, :file])
  end

  def set_create_form_parameters
    @event = Event.where(id: params[:event_id]).first
    events = Event.future.to_a
    events += [@event] unless @event.nil?
    @events_collection = events.collect { |event| [event.name, event.id] }
  end

  ##
  # Overrides
  ##

  def resource_class
    Admin::Questionnaires::Questionnaire
  end

  def permitted_create_params
    [:event_id] + permitted_update_params
  end

  def permitted_update_params
    [:name, questions_attributes: [:id, :_destroy, :question_text, :response_type]]
  end

  def base_index_query
    q = params[:q]

    @q = @questionnaires.ransack(q)

    @show_current_term_only = q.nil?

    # Set the range to the current term by default.
    @q.event_end_date_gt = helpers.start_of_term if @show_current_term_only
    @q.event_start_date_lt = helpers.end_of_term if @show_current_term_only

    return @q.result
  end

  def includes_args
    [:event]
  end

  def order_args
    ['id DESC']
  end

  def load_index_resources
    @questionnaires = super.group_by { |questionnaire| questionnaire.event.name }
  end
end
