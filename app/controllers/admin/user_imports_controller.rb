# frozen_string_literal: true

##
# Controller for bulk importing users (without activating membership).
# Creates user accounts from spreadsheet/paste data with smart matching.
##
class Admin::UserImportsController < AdminController
  include Importable

  authorize_resource class: false

  def new
    @title = "Bulk User Import"
  end

  def preview
    data, input_type = parse_import_params

    if data.blank?
      helpers.append_to_flash(:error, "Please paste data or upload a file")
      redirect_to new_admin_user_import_path
      return
    end

    @import = UserImport.new(data, input_type: input_type, import_mode: :user)

    unless @import.valid?
      helpers.append_to_flash(:error, @import.errors.join(", "))
      redirect_to new_admin_user_import_path
      return
    end

    # Store in cache to avoid session cookie overflow (4KB limit)
    @cache_key = generate_import_cache_key("user_import")
    write_import_cache(@cache_key, serialize_import(@import.categorized))
    @title = "Review User Import"
  end

  def confirm
    categorized = read_and_clear_cache(params[:cache_key])

    if categorized.blank?
      helpers.append_to_flash(:error, "No pending import found. Please start over.")
      redirect_to new_admin_user_import_path
      return
    end

    actions = params[:actions] || {}
    results = { created: 0, linked: 0, skipped: 0 }

    # Process all buckets
    all_items = categorized.values.flatten
    all_items.each do |item|
      index = item["index"].to_s
      action = actions[index]
      row = item["row"].with_indifferent_access

      case action
      when "create"
        create_user_from_row(row)
        results[:created] += 1
      when "link"
        # User already exists, no action needed (just acknowledging the link)
        results[:linked] += 1
      when "skip", nil
        results[:skipped] += 1
      end
    end

    helpers.append_to_flash(:success, "Import complete: #{results[:created]} created, #{results[:linked]} linked to existing, #{results[:skipped]} skipped")
    redirect_to admin_users_path
  end
end
