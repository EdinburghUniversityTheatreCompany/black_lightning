# frozen_string_literal: true

# Bulk-imports an event's crew: creates any missing users and adds everyone to the team.
class Admin::ShowCrewImportsController < AdminController
  include Importable

  before_action :load_event
  before_action { authorize! :update, @event }

  def new
    @title = "Bulk Crew Import for #{@event.name}"
  end

  def preview
    data, input_type = parse_import_params

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

    @existing_team_members = categorize_existing_team_members(@import)

    # Store in cache to avoid session cookie overflow (4KB limit)
    @cache_key = cache_import("crew_import", {
      event_id: @event.id,
      categorized: serialize_import(@import.categorized),
      existing_team_members: @existing_team_members
    })
    @title = "Review Crew Import for #{@event.name}"
  end

  def confirm
    import_data = read_and_clear_cache(params[:cache_key])

    if import_data.blank? || import_data["event_id"].to_i != @event.id
      helpers.append_to_flash(:error, "No pending import found. Please start over.")
      redirect_to new_admin_show_show_crew_import_path(@event)
      return
    end

    actions = params[:actions] || {}
    existing_actions = params[:existing_actions] || {}
    results = { created: 0, added: 0, updated: 0, skipped: 0, errors: [] }

    import_data["categorized"].values.flatten.each do |item|
      row = item["row"].with_indifferent_access

      user = case actions[item["index"].to_s]
      when "create"
        create_user_from_row(row).tap do |created|
          results[:created] += 1
          created.send_welcome_email
        end
      when "link" then User.find_by(id: item["existing_user_id"])
      when /\Alink_(\d+)\z/ then User.find_by(id: $1.to_i)
      when "skip"
        results[:skipped] += 1
        next
      else next
      end
      next unless user && row[:position].present?

      @event.team_members.find_or_initialize_by(user: user).update!(position: row[:position])
      results[:added] += 1
    rescue ActiveRecord::RecordInvalid => e
      results[:errors] << "#{row[:original_name]}: #{e.record.errors.full_messages.to_sentence}"
    end

    (import_data["existing_team_members"] || {}).each do |user_id, data|
      action = existing_actions[user_id.to_s]
      if action == "skip"
        results[:skipped] += 1
        next
      end
      next unless action.in?(%w[merge replace])

      team_member = @event.team_members.find_by(user_id: user_id)
      position = data["new_position"]
      next unless team_member && position.present?

      position = [ team_member.position, position ].join("/").split("/").map(&:strip).compact_blank.uniq.join(" / ") if action == "merge"
      team_member.update!(position: position)
      results[:updated] += 1
    end

    message = "Import complete: #{results[:created]} users created, #{results[:added]} added to crew, #{results[:updated]} positions updated, #{results[:skipped]} skipped"
    message += ". Errors: #{results[:errors].join('; ')}" if results[:errors].any?
    helpers.append_to_flash(:success, message)
    redirect_to [ :admin, @event ]
  end

  private

  def load_event
    event_id = params[:show_id] || params[:season_id] || params[:workshop_id] || params[:event_id] || params[:id]
    @event = Event.find_by!(slug: event_id)
  end

  def categorize_existing_team_members(import)
    team = @event.team_members.index_by(&:user_id)

    import.categorized.values.flatten.each_with_object({}) do |item, existing|
      (item[:existing_users] || [ item[:existing_user] ].compact).each do |user|
        next unless (member = team[user.id])

        existing[user.id] = { "user_name" => user.name_or_email, "current_position" => member.position, "new_position" => item[:row][:position] }
      end
    end
  end
end
