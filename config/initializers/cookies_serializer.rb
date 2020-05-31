# Be sure to restart your server when you modify this file.

# Specify a serializer for the signed and encrypted cookie jars.
# Valid options are :json, :marshal, and :hybrid.
# Hybrid will migrate existing Marhsal-serialized cookies into the JSON-based format that's used from rails 4.1 onwards.
# It started out as :json, but then was changed to :hybrid and I don't know if changing it back to :json would break things.
Rails.application.config.action_dispatch.cookies_serializer = :hybrid
