Paperclip.interpolates :slug do |attachment, _style|
  attachment.instance.slug
  PaperTrail.config.track_associations = false
end
