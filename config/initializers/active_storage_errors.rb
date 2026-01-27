# frozen_string_literal: true

# Add Honeybadger context for ActiveStorage errors.
# This helps debug issues with image processing by including blob details in error reports.
ActiveSupport::Notifications.subscribe(/active_storage/) do |name, start, finish, id, payload|
  if payload[:exception]
    blob = payload[:blob] || payload[:key]
    Honeybadger.context(
      active_storage_blob_id: blob&.id,
      active_storage_blob_key: blob&.key,
      active_storage_blob_filename: blob&.filename&.to_s,
      active_storage_event: name
    )
  end
end
