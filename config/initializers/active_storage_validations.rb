# frozen_string_literal: true

# active_storage_validations 4.0 started deriving an HTML `accept` attribute on
# every `file_field` from its model's content_type validator. Switched back off,
# because `Attachment::ALLOWED_CONTENT_TYPES` is deliberately a SERVER-side
# allow-list with no browser filter in front of it, and the types most likely to
# be rejected wrongly are the container-based ones (.mscz / .mxl / .musicxml)
# that only resolve correctly because they are registered with Marcel against a
# `parent:` — an `accept` list matched by the browser on extension and reported
# MIME type is exactly where those go wrong, and the failure is a file picker
# that greys out a file the server would have taken.
#
# Turning it ON is a real UX improvement and a deliberate decision to make, not
# a default to inherit: it needs a pass over every upload form first.
ActiveStorageValidations.infer_file_field_accept = false
