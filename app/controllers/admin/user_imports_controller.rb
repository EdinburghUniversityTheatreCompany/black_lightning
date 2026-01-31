# frozen_string_literal: true

##
# Controller for bulk importing users (without activating membership).
# Creates user accounts from spreadsheet/paste data with smart matching.
##
class Admin::UserImportsController < AdminController
  authorize_resource class: false

  def new
    @title = "Bulk User Import"
  end

  def preview
    data = params[:paste_data].presence || params[:xlsx_file]
    input_type = params[:paste_data].present? ? :paste : :xlsx

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
    @cache_key = "user_import_#{SecureRandom.uuid}"
    Rails.cache.write(@cache_key, serialize_import(@import.categorized), expires_in: 1.hour)
    @title = "Review User Import"
  end

  def confirm
    cache_key = params[:cache_key]
    categorized = cache_key.present? ? Rails.cache.read(cache_key) : nil
    Rails.cache.delete(cache_key) if categorized.present?

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
        create_user(row)
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

  private

  def serialize_import(categorized)
    # Convert to a serializable format for session storage
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
end
