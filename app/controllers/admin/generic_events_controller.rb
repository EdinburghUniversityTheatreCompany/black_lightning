# For the few things that are shared between the controllers of the events.

class Admin::GenericEventsController < AdminController
  include GenericestEventsController

  load_and_authorize_resource find_by: :slug

  def update
    # Set the previous user ids to see who the NEW debtors are.
    @previous_user_ids = get_resource.users.ids

    super
  end

  private

  def index_filename
    'admin/events/index'
  end

  def permitted_params
    # Returns a hash with base permitted params to prevent accidentally omitting one.
    return [
      :publicity_text, :members_only_text, :name, :slug, :tagline, 
      :pretix_slug_override, :pretix_shown, :pretix_view,
      :author, :venue, :venue_id, :season, :season_id,
      :xts_id, :is_public, :image, :proposal, :proposal_id,
      :start_date, :end_date, :price, :spark_seat_slug, event_tag_ids: [],
      pictures_attributes: [:id, :_destroy, :description, :image, :access_level, picture_tag_ids: []],
      team_members_attributes: [:id, :_destroy, :position, :user, :user_id, :proposal],
      attachments_attributes: [:id, :_destroy, :name, :file, :access_level, attachment_tag_ids: []],
      video_links_attributes: [:id, :_destroy, :name, :link, :access_level, :order]
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
      if new_debtors.any? && @show.start_date > helpers.start_of_year
        new_debtors_string = new_debtors.collect(&:name).to_sentence
        helpers.append_to_flash(:notice, "The show was successfully updated, but #{new_debtors_string} #{'is'.pluralize(new_debtors.count)} in debt.")

        ShowMailer.warn_committee_about_debtors_added_to_show(@show, new_debtors_string, @current_user).deliver_later
      end
    end

    super
  end

  def index_query_params
    { is_public: false } if params[:show_private_only] == '1'
  end
end
