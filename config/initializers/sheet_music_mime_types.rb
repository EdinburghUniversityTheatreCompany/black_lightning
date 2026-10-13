# Be sure to restart your server when you modify this file.
#
# Registers music-notation content types with Marcel so uploads are recognised and allowed by
# Attachment::ALLOWED_CONTENT_TYPES: active_storage_validations resolves a type with
# Marcel::MimeType.for(declared_type:, name:), so Marcel must map the extension. It already knows
# MIDI (.mid, .midi) and Sibelius (.sib); below are the formats it lacks, plus MusicXML's container fix.

# MuseScore: .mscz is a zip container, .mscx is uncompressed XML.
Marcel::MimeType.extend "application/x-musescore",     extensions: %w[mscz], parents: %w[application/zip]
Marcel::MimeType.extend "application/x-musescore+xml", extensions: %w[mscx], parents: %w[application/xml]

# Plain-text notation source formats.
Marcel::MimeType.extend "text/x-lilypond", extensions: %w[ly],  parents: %w[text/plain]
Marcel::MimeType.extend "text/vnd.abc",    extensions: %w[abc], parents: %w[text/plain]

# Container formats need a `parents:` entry, or the container magic wins and Marcel resolves them to
# bare application/zip or application/xml. MusicXML is known to Marcel but hits the same. A parent
# keeps the specific type and leaves plain .zip/.xml uploads unaffected.
Marcel::MimeType.extend "application/vnd.recordare.musicxml+xml", extensions: %w[musicxml], parents: %w[application/xml]
Marcel::MimeType.extend "application/vnd.recordare.musicxml",     extensions: %w[mxl],      parents: %w[application/zip]
