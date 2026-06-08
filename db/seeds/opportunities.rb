eutc = Company.find_by(name: "Edinburgh University Theatre Company")
gutter = Company.find_by(name: "Gutter Theatre")
creator = User.find_by(email: "admin@bedlamtheatre.co.uk")

# Depends on the companies and users seeds having run first.
if [ eutc, gutter, creator ].any?(&:nil?)
  seed_puts "Skipping opportunities: seed companies and users first."
  return
end

# Internal (EUTC) posting with no title — heading is derived from company + project.
eurydice = find_or_seed(Opportunity, { project: "Eurydice", company: eutc }, {
  description: "Our spring production of **Eurydice** is recruiting a full crew. Get in touch!",
  author: "Sarah Ruhl",
  creator: creator,
  approved: true,
  expiry_date: 3.weeks.from_now,
  compensation_type: :unpaid,
  experience_level: :student,
  email_visibility: :everyone,
  contact_email: "casting@bedlamtheatre.co.uk"
})

if eurydice.roles.empty?
  eurydice.roles.create!([
    { position: "Stage Manager", category: :stage, ordering: 0 },
    { position: "Set Manager", category: :set, note: "Build weekends only", ordering: 1 },
    { position: "Sound Technician", category: :sound, ordering: 2 }
  ])
end

# External submission (no account): captured via submitter name/email.
foh = find_or_seed(Opportunity, { title: "Front of House volunteers", company: gutter }, {
  description: "External company seeking front of house volunteers for a week-long run.",
  approved: true,
  expiry_date: 5.weeks.from_now,
  compensation_type: :paid,
  experience_level: :any,
  email_visibility: :everyone,
  apply_url: "https://example.com/apply",
  submitter_name: "Jane Producer",
  submitter_email: "jane@example.com"
})

if foh.roles.empty?
  foh.roles.create!([ { position: "Front of House Manager", category: :foh, ordering: 0 } ])
end
