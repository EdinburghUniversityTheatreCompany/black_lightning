# frozen_string_literal: true

# Bulk membership import from xlsx or pasted TSV: matches rows to users and activates them.
class Admin::MembershipImportsController < AdminController
  include Importable

  authorize_resource class: false

  def new
    @title = "Bulk Membership Import"
  end

  def preview
    data, input_type = parse_import_params

    if data.blank?
      helpers.append_to_flash(:error, "Please provide data to import (paste or upload)")
      redirect_to new_admin_membership_import_path
      return
    end

    @import = MembershipImport.new(data, input_type: input_type)
    @title = "Review Import"

    unless @import.valid?
      helpers.append_to_flash(:error, @import.errors.join(", "))
      redirect_to new_admin_membership_import_path
      return
    end

    # Store in cache to avoid session cookie overflow (4KB limit)
    @cache_key = generate_import_cache_key("membership_import")
    write_import_cache(@cache_key, serialize_import(@import.categorized))
  end

  def confirm
    categorized = read_and_clear_cache(params[:cache_key])

    if categorized.blank?
      helpers.append_to_flash(:error, "No pending import found. Please start over.")
      redirect_to new_admin_membership_import_path
      return
    end

    actions = params[:actions] || {}
    results = process_import(categorized, actions)

    helpers.append_to_flash(:success, format_results(results))
    redirect_to new_admin_membership_import_path
  end

  private

  def process_import(categorized, actions)
    results = { activated: 0, created: 0, merged: 0, skipped: 0, errors: [] }
    @synced_user_ids = []

    categorized.each do |bucket, items|
      items.each do |item|
        action = determine_action(bucket, item["index"], actions)
        process_item(item, action, results)
      end
    end

    # One enqueue for the whole import: a row can activate a user AND rewrite their
    # placeholder email. The nightly reconcile is the backstop.
    Pretix::SyncMembershipJob.enqueue_for(@synced_user_ids)

    results
  end

  def determine_action(bucket, index, actions)
    explicit_action = actions[index.to_s]
    return explicit_action if explicit_action.present?

    case bucket.to_sym
    when :already_active
      "skip"
    when :activate_by_id, :activate_by_email
      "activate"
    when :propose_merge
      "skip" # needs an explicit decision
    when :create_new
      "create"
    else
      "skip"
    end
  end

  def process_item(item, action, results)
    row = item["row"].with_indifferent_access
    case action
    when "activate"
      activate_user(User.find_by(id: item["existing_user_id"]), row, results)
    when "create"
      create_and_activate_user(row, results)
    when /\Amerge_(\d+)\z/
      # a candidate picked from a multi-candidate fuzzy match
      merge_and_activate(User.find_by(id: $1.to_i), row, results)
    when "skip"
      results[:skipped] += 1
    end
  rescue StandardError => e
    results[:errors] << "Error processing #{row[:original_name]}: #{e.message}"
  end

  def activate_user(user, row, results)
    return results[:errors] << "User not found for activation" unless user

    update_email_if_unknown(user, row[:email])
    update_ids_if_missing(user, row)
    user.add_role(:member)
    user.send_welcome_email
    @synced_user_ids << user.id
    results[:activated] += 1
  end

  def create_and_activate_user(row, results)
    email = row[:email].presence || generate_unknown_email

    user = User.new_user(
      email: email,
      first_name: row[:first_name],
      last_name: row[:last_name],
      student_id: row[:student_id],
      associate_id: row[:associate_id]
    )

    if user.save
      user.add_role(:member)
      user.send_welcome_email
      @synced_user_ids << user.id
      results[:created] += 1
    else
      results[:errors] << "Failed to create #{row[:original_name]}: #{user.errors.full_messages.join(', ')}"
    end
  end

  def merge_and_activate(existing_user, row, results)
    return results[:errors] << "User not found for merge" unless existing_user

    update_email_if_unknown(existing_user, row[:email])
    update_ids_if_missing(existing_user, row)

    if existing_user.first_name.blank? && row[:first_name].present?
      existing_user.update(first_name: row[:first_name])
    end
    if existing_user.last_name.blank? && row[:last_name].present?
      existing_user.update(last_name: row[:last_name])
    end

    unless existing_user.member?
      existing_user.add_role(:member)
      existing_user.send_welcome_email
    end

    # Collected even when the role was already held: the placeholder email may have
    # been rewritten, and pretix matches on email.
    @synced_user_ids << existing_user.id
    results[:merged] += 1
  end

  def update_email_if_unknown(user, new_email)
    return unless new_email.present?
    return unless user.email.match?(/\Aunknown_.*@bedlamtheatre\.co\.uk\z/)

    user.update(email: new_email)
  end

  def update_ids_if_missing(user, row)
    user.update(student_id: row[:student_id]) if row[:student_id].present? && user.student_id.blank?
    user.update(associate_id: row[:associate_id]) if row[:associate_id].present? && user.associate_id.blank?
  end

  def generate_unknown_email
    "unknown_#{SecureRandom.hex(8)}@bedlamtheatre.co.uk"
  end

  def format_results(results)
    parts = []
    parts << "#{results[:activated]} activated" if results[:activated] > 0
    parts << "#{results[:created]} created" if results[:created] > 0
    parts << "#{results[:merged]} merged" if results[:merged] > 0
    parts << "#{results[:skipped]} skipped" if results[:skipped] > 0

    message = "Import complete: #{parts.join(', ')}"
    message += ". Errors: #{results[:errors].join('; ')}" if results[:errors].any?
    message
  end
end
