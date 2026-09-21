# frozen_string_literal: true

# active_storage_validations 4.0 started deriving an HTML `accept` from each
# model's content_type validator. Off, because Attachment::ALLOWED_CONTENT_TYPES
# is a server-side allow-list by design and half of it is types no browser
# knows (application/x-musescore, application/x-sibelius, text/x-lilypond) — an
# `accept` built from those greys out files the server would have taken.
# Turning it on is a UX decision that needs a pass over every upload form.
ActiveStorageValidations.infer_file_field_accept = false
