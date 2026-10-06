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

    categorized.values.flatten.each do |item|
      process_item(item, actions[item["index"].to_s], results)
    end

    # One enqueue for the whole import: a row can activate a user AND rewrite their
    # placeholder email. The nightly reconcile is the backstop.
    Pretix::SyncMembershipJob.enqueue_for(@synced_user_ids)

    results
  end

  def process_item(item, action, results)
    row = item["row"].with_indifferent_access
    case action
    when "activate"
      user = User.find_by(id: item["existing_user_id"])
      return results[:errors] << "User not found for activation" unless user

      fill_blanks(user, row)
      activate(user)
      results[:activated] += 1
    when "create"
      activate(create_user_from_row(row))
      results[:created] += 1
    when /\Amerge_(\d+)\z/
      # a candidate picked from a multi-candidate fuzzy match
      user = User.find_by(id: $1.to_i)
      return results[:errors] << "User not found for merge" unless user

      fill_blanks(user, row, names: true)
      activate(user)
      results[:merged] += 1
    else
      results[:skipped] += 1
    end
  rescue StandardError => e
    results[:errors] << "Error processing #{row[:original_name]}: #{e.message}"
  end

  def activate(user)
    unless user.member?
      user.add_role(:member)
      user.send_welcome_email
    end

    # Collected even when the role was already held: the placeholder email may have
    # been rewritten, and pretix matches on email.
    @synced_user_ids << user.id
  end

  # One update per attribute, so a failing write (an email already taken) does not block the rest.
  def fill_blanks(user, row, names: false)
    user.update(email: row[:email]) if row[:email].present? && user.email.match?(/\Aunknown_.*@bedlamtheatre\.co\.uk\z/)

    (%i[student_id associate_id] + (names ? %i[first_name last_name] : [])).each do |attribute|
      user.update(attribute => row[attribute]) if row[attribute].present? && user[attribute].blank?
    end
  end

  def format_results(results)
    parts = results.slice(:activated, :created, :merged, :skipped).filter_map { |key, count| "#{count} #{key}" if count.positive? }

    message = "Import complete: #{parts.join(', ')}"
    message += ". Errors: #{results[:errors].join('; ')}" if results[:errors].any?
    message
  end
end
