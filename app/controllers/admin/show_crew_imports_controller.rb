# frozen_string_literal: true

##
# Controller for bulk importing show crew (users + team memberships).
# Creates user accounts and adds them to an event's team.
##
class Admin::ShowCrewImportsController < AdminController
  before_action :load_event

  def new
    authorize! :update, @event
    @title = "Bulk Crew Import for #{@event.name}"
  end

  def preview
    authorize! :update, @event

    data = params[:paste_data].presence || params[:xlsx_file]
    input_type = params[:paste_data].present? ? :paste : :xlsx

    if data.blank?
      helpers.append_to_flash(:error, "Please paste data or upload a file")
      redirect_to new_admin_show_show_crew_import_path(@event)
      return
    end

    @import = UserImport.new(data, input_type: input_type, import_mode: :crew)

    unless @import.valid?
      helpers.append_to_flash(:error, @import.errors.join(", "))
      redirect_to new_admin_show_show_crew_import_path(@event)
      return
    end

    # Check for existing team members and categorize them
    @existing_team_members = categorize_existing_team_members(@import)

    # Store in cache to avoid session cookie overflow (4KB limit)
    @cache_key = "crew_import_#{SecureRandom.uuid}"
    Rails.cache.write(@cache_key, {
      event_id: @event.id,
      categorized: serialize_import(@import.categorized),
      existing_team_members: @existing_team_members
    }, expires_in: 1.hour)
    @title = "Review Crew Import for #{@event.name}"
  end

  def confirm
    authorize! :update, @event

    cache_key = params[:cache_key]
    import_data = cache_key.present? ? Rails.cache.read(cache_key) : nil
    Rails.cache.delete(cache_key) if import_data.present?

    if import_data.blank? || import_data["event_id"].to_i != @event.id
      helpers.append_to_flash(:error, "No pending import found. Please start over.")
      redirect_to new_admin_show_show_crew_import_path(@event)
      return
    end

    categorized = import_data["categorized"]
    existing_team_members = import_data["existing_team_members"] || {}
    actions = params[:actions] || {}
    existing_actions = params[:existing_actions] || {}

    results = { created: 0, added: 0, updated: 0, skipped: 0 }

    # Process new/matched users
    all_items = categorized.values.flatten
    all_items.each do |item|
      index = item["index"].to_s
      action = actions[index]
      row = item["row"].with_indifferent_access

      user = case action
      when "create"
        results[:created] += 1
        create_user(row)
      when "link"
        # Use existing user
        User.find_by(id: item["existing_user_id"])
      when "skip", nil
        results[:skipped] += 1
        next
      else
        next
      end

      next unless user

      # Add to team if position is provided
      if row[:position].present?
        add_or_update_team_member(user, row[:position])
        results[:added] += 1
      end
    end

    # Process existing team members
    existing_team_members.each do |user_id, data|
      user_id = user_id.to_i
      action = existing_actions[user_id.to_s]
      new_position = data["new_position"]

      case action
      when "skip"
        results[:skipped] += 1
      when "merge"
        team_member = @event.team_members.find_by(user_id: user_id)
        if team_member && new_position.present?
          merged_position = [ team_member.position, new_position ].reject(&:blank?).uniq.join(", ")
          team_member.update!(position: merged_position)
          results[:updated] += 1
        end
      when "replace"
        team_member = @event.team_members.find_by(user_id: user_id)
        if team_member && new_position.present?
          team_member.update!(position: new_position)
          results[:updated] += 1
        end
      end
    end

    helpers.append_to_flash(:success, "Import complete: #{results[:created]} users created, #{results[:added]} added to crew, #{results[:updated]} positions updated, #{results[:skipped]} skipped")
    redirect_to admin_show_path(@event)
  end

  private

  def load_event
    @event = Show.find_by_slug(params[:show_id])
  end

  def serialize_import(categorized)
    categorized.transform_values do |items|
      items.map do |item|
        {
          "row" => item[:row],
          "existing_user_id" => item[:existing_user]&.id,
          "index" => item[:index]
        }
      end
    end
  end

  def categorize_existing_team_members(import)
    existing = {}

    # Check each imported row to see if the user is already on the team
    import.categorized.each do |bucket, items|
      items.each do |item|
        user = item[:existing_user]
        next unless user

        team_member = @event.team_members.find_by(user_id: user.id)
        next unless team_member

        existing[user.id] = {
          "user_id" => user.id,
          "user_name" => user.name_or_email,
          "current_position" => team_member.position,
          "new_position" => item[:row][:position],
          "index" => item[:index]
        }
      end
    end

    existing
  end

  def create_user(row)
    email = row[:email].presence || generate_placeholder_email

    user = User.new(
      email: email,
      first_name: row[:first_name],
      last_name: row[:last_name],
      student_id: row[:student_id],
      associate_id: row[:associate_id],
      password: Devise.friendly_token[0, 20]
    )

    user.save!
    user
  end

  def generate_placeholder_email
    "unknown_#{SecureRandom.hex(8)}@bedlamtheatre.co.uk"
  end

  def add_or_update_team_member(user, position)
    existing = @event.team_members.find_by(user_id: user.id)

    if existing
      # User already on team - this shouldn't happen here, but just in case
      existing.update!(position: position)
    else
      @event.team_members.create!(user: user, position: position)
    end
  end
end
