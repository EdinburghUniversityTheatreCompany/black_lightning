# Be sure to restart your server when you modify this file.
#
# Registers sheet-music / music-notation content types with Marcel so that
# attachment uploads of these formats are recognised (and therefore allowed by
# Attachment::ALLOWED_CONTENT_TYPES). active_storage_validations resolves an
# upload's content type via Marcel::MimeType.for(declared_type:, name:), so a
# format only validates correctly if Marcel maps its extension to a known type.
#
# Marcel already knows: MusicXML (.musicxml, .mxl), MIDI (.mid, .midi) and
# Sibelius (.sib). The registrations below add the formats it does not know and
# fix container-based detection for the two zip/xml MusicXML formats.

# MuseScore — .mscz is a zip container, .mscx is uncompressed XML.
Marcel::MimeType.extend "application/x-musescore",     extensions: %w[mscz], parents: %w[application/zip]
Marcel::MimeType.extend "application/x-musescore+xml", extensions: %w[mscx], parents: %w[application/xml]

# Plain-text notation source formats.
Marcel::MimeType.extend "text/x-lilypond", extensions: %w[ly],  parents: %w[text/plain]
Marcel::MimeType.extend "text/vnd.abc",    extensions: %w[abc], parents: %w[text/plain]

# MusicXML is already known to Marcel, but its container magic (zip for .mxl,
# xml for .musicxml) otherwise wins, resolving these to bare application/zip /
# application/xml. Declaring the container as a parent lets Marcel keep the
# specific MusicXML type while leaving plain .zip/.xml uploads unaffected.
Marcel::MimeType.extend "application/vnd.recordare.musicxml+xml", extensions: %w[musicxml], parents: %w[application/xml]
Marcel::MimeType.extend "application/vnd.recordare.musicxml",     extensions: %w[mxl],      parents: %w[application/zip]
