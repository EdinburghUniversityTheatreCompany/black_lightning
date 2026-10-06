# frozen_string_literal: true

# Adds blob details to Honeybadger reports of ActiveStorage errors, to debug image processing.
ActiveSupport::Notifications.subscribe(/active_storage/) do |name, start, finish, id, payload|
  if payload[:exception]
    blob = payload[:blob]
    Honeybadger.context(
      active_storage_blob_id: blob&.id,
      active_storage_blob_key: blob&.key || payload[:key],
      active_storage_blob_filename: blob&.filename&.to_s,
      active_storage_event: name
    )
  end
end
