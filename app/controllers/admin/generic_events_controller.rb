# For the few things that are shared between the controllers of the events.

class Admin::GenericEventsController < AdminController
  include GenericestEventsController

  load_and_authorize_resource find_by: :slug
  skip_authorize_resource only: %i[update_debt_settings]

  def update
    # Set the previous user ids to see who the NEW debtors are.
    @previous_user_ids = get_resource.users.ids

    super
  end

  # PATCH admin/shows/1/update_debt_settings
  # PATCH admin/workshops/1/update_debt_settings
  # PATCH admin/seasons/1/update_debt_settings
  # PATCH admin/generic_events/1/update_debt_settings
  def update_debt_settings
    authorize! :create, Admin::MaintenanceDebt
    authorize! :create, Admin::StaffingDebt

    unless get_resource.end_date > helpers.start_of_year
      helpers.append_to_flash(:error, "Debt settings can only be configured for events in the current academic year or later.")
      redirect_to polymorphic_path([ :admin, get_resource ])
      return
    end

    if get_resource.update(debt_settings_params)
      result = get_resource.sync_debts_for_all_users
      total_created = result[:maintenance] + result[:staffing]

      if total_created > 0
        helpers.append_to_flash(:success, "Debt settings saved. Created #{helpers.pluralize(result[:maintenance], 'maintenance debt')} and #{helpers.pluralize(result[:staffing], 'staffing debt')}.")
      else
        helpers.append_to_flash(:success, "Debt settings saved.")
      end
    else
      helpers.append_to_flash(:error, "Could not save debt settings: #{get_resource.errors.full_messages.to_sentence}")
    end

    redirect_to polymorphic_path([ :admin, get_resource ])
  end

  private

  def index_filename
    "admin/events/index"
  end

  def permitted_params
    # Returns a hash with base permitted params to prevent accidentally omitting one.
    [
      :publicity_text, :members_only_text, :name, :slug, :tagline,
      :pretix_slug_override, :pretix_shown, :pretix_view, :content_warnings,
      :author, :venue, :venue_id, :season, :season_id,
      :xts_id, :is_public, :image, :proposal, :proposal_id,
      :start_date, :end_date, :price, :spark_seat_slug,
      :maintenance_debt_start, :staffing_debt_start,
      :maintenance_debt_amount, :staffing_debt_amount,
      event_tag_ids: [],
      pictures_attributes: [ :id, :_destroy, :description, :image, :access_level, picture_tag_ids: [] ],
      team_members_attributes: [ :id, :_destroy, :position, :user, :user_id, :proposal ],
      attachments_attributes: [ :id, :_destroy, :name, :file, :access_level, attachment_tag_ids: [] ],
      video_links_attributes: [ :id, :_destroy, :name, :link, :access_level, :order ],
      reviews_attributes: [ :id, :_destroy, :title, :url, :body, :rating, :review_date, :organisation, :reviewer, :event_id ]
    ]
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
      if new_debtors.any? && get_resource.start_date > helpers.start_of_year
        new_debtors_string = new_debtors.collect(&:name).to_sentence
        helpers.append_to_flash(:success, "The show was successfully updated, but #{new_debtors_string} #{'is'.pluralize(new_debtors.count)} in debt.")

        ShowMailer.warn_committee_about_debtors_added_to_show(get_resource, new_debtors_string, @current_user).deliver_later
      end
    end

    super
  end

  def index_query_params
    { is_public: false } if params[:show_private_only] == "1"
  end

  def debt_settings_params
    params.require(resource_name).permit(
      :maintenance_debt_amount, :maintenance_debt_start,
      :staffing_debt_amount, :staffing_debt_start
    )
  end
end
