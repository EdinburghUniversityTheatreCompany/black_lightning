hamlet = Show.find_by(slug: "hamlet")
cabaret = Show.find_by(slug: "cabaret")
rent = Show.find_by(slug: "rent")

header_path      = Rails.root.join("app/assets/images/Header.jpg")
background_path  = Rails.root.join("app/assets/images/card_background.jpg")
logo_path        = Rails.root.join("app/assets/images/BedlamLogoBW.png")

# ── Picture Tags ───────────────────────────────────────────────────────────────
production_tag = PictureTag.find_or_create_by(name: "Production Photos") do |t|
  t.description = "Photos taken during the run of a show."
end

rehearsal_tag = PictureTag.find_or_create_by(name: "Rehearsal Photos") do |t|
  t.description = "Photos taken during rehearsals."
end

# ── Attachment Tags ────────────────────────────────────────────────────────────
script_tag = AttachmentTag.find_or_create_by(name: "Script") do |t|
  t.description = "Show scripts and texts."
end

schedule_tag = AttachmentTag.find_or_create_by(name: "Schedule") do |t|
  t.description = "Rehearsal and production schedules."
end

# ── Pictures on shows ─────────────────────────────────────────────────────────
[
  [ hamlet,  "Hamlet production photo", header_path,     "header.jpg",      [ production_tag ] ],
  [ hamlet,  "Hamlet rehearsal photo",  background_path, "rehearsal.jpg",   [ rehearsal_tag ] ],
  [ cabaret, "Cabaret production photo", header_path,    "cabaret.jpg",     [ production_tag ] ],
  [ rent,    "Rent production photo",   background_path, "rent.jpg",        [ production_tag ] ],
  [ rent,    "Rent rehearsal photo",    header_path,     "rent_rehearsal.jpg", [ rehearsal_tag ] ]
].each do |show, description, path, filename, tags|
  next unless show
  next if show.pictures.where(description: description).exists?

  picture = Picture.new(
    gallery: show,
    description: description,
    access_level: 1  # Member
  )
  picture.image.attach(io: File.open(path), filename: filename, content_type: "image/jpeg")
  picture.save!
  picture.picture_tags = tags
end

# ── Attachments on shows ───────────────────────────────────────────────────────
# Create a small text file to use as a seed attachment
schedule_file = Tempfile.new([ "schedule", ".txt" ])
schedule_file.write("Week 1: Blocking\nWeek 2: Off-book\nWeek 3: Tech\nWeek 4: Run")
schedule_file.rewind

[
  [ hamlet, "Hamlet Rehearsal Schedule", schedule_tag ],
  [ rent,   "Rent Rehearsal Schedule",   schedule_tag ]
].each do |show, name, tag|
  next unless show
  next if Attachment.where(name: name).exists?

  attachment = Attachment.new(name: name, item: show, access_level: 1)
  attachment.file.attach(io: File.open(schedule_file.path), filename: "#{name.parameterize}.txt", content_type: "text/plain")
  attachment.save!
  attachment.attachment_tags << tag
end

schedule_file.close
schedule_file.unlink

# ── Attachments on editable blocks (logo on About page) ───────────────────────
about_block = Admin::EditableBlock.find_by(url: "about")
if about_block && Attachment.where(name: "Bedlam Theatre Logo").none?
  attachment = Attachment.new(name: "Bedlam Theatre Logo", item: about_block, access_level: 2)  # Everyone
  attachment.file.attach(io: File.open(logo_path), filename: "bedlam-logo.png", content_type: "image/png")
  attachment.save!
end

# ── Video links on shows ───────────────────────────────────────────────────────
[
  [ hamlet,  "Hamlet Trailer",  "https://www.youtube.com/watch?v=dQw4w9WgXcQ", 1 ],
  [ cabaret, "Cabaret Trailer", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", 1 ],
  [ rent,    "Rent Trailer",    "https://www.youtube.com/watch?v=dQw4w9WgXcQ", 2 ]  # Everyone
].each do |show, name, link, access_level|
  next unless show
  next if show.video_links.where(name: name).exists?

  VideoLink.create!(name: name, link: link, access_level: access_level, item: show, order: 1)
end
