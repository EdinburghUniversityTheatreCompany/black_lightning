# For the few things that are shared between the controllers of the events.

class Admin::EventsController < AdminController
  include GenericController

  load_and_authorize_resource find_by: :slug

  def index
    @events = load_index_resources

    if params[:commit] == 'Random'
      redirect_to(Event.find(@events.pluck(:id).sample))
      return
    end

    respond_to do |format|
      format.html { render 'admin/events/index' }
      format.json { render json: @events }
    end
  end

  def update
    # Set the previous user ids to see who the NEW debtors are.
    @previous_user_ids = get_resource.users.ids

    super
  end

  private

  def order_args
    # Dealt with by default scope.
    nil
  end

  def permitted_params
    return Event.base_permitted_params
  end

  def should_paginate
    params.nil? || params[:commit] != 'Random'
  end

  def on_update_success
    # Should set @previous_user_ids in the update action.

    # Used to check any new users being added are not in debt.
    if params[resource_name][:team_members_attributes]
      parameter_user_ids = params[resource_name][:team_members_attributes].values.collect { |e| e[:user_id].to_i }.uniq
      new_user_ids = parameter_user_ids - @previous_user_ids

      new_users = User.where(id: new_user_ids)
      new_debtors = new_users.select(&:in_debt)

      # Only notify debtors if the start date is after the start of the current academic year.
      if new_debtors.any? && @show.start_date > helpers.start_of_year
        new_debtors_string = new_debtors.collect(&:name).to_sentence
        helpers.append_to_flash(:notice, "The show was successfully updated, but #{new_debtors_string} #{'is'.pluralize(new_debtors.count)} in debt.")

        ShowMailer.warn_committee_about_debtors_added_to_show(@show, new_debtors_string, @current_user).deliver_later
      end
    end

    super
  end
end
