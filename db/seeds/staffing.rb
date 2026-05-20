alice = User.find_by!(email: "alice.jones@sms.ed.ac.uk")
ben = User.find_by!(email: "ben.mackenzie@sms.ed.ac.uk")
chloe = User.find_by!(email: "chloe.harvey@sms.ed.ac.uk")
david = User.find_by!(email: "david.osei@sms.ed.ac.uk")
emma = User.find_by!(email: "emma.thornton@sms.ed.ac.uk")
finn = User.find_by!(email: "finn.obrien@sms.ed.ac.uk")
grace = User.find_by!(email: "grace.liu@sms.ed.ac.uk")
harry = User.find_by!(email: "harry.walsh@sms.ed.ac.uk")
isla = User.find_by!(email: "isla.ferguson@sms.ed.ac.uk")

# ── Staffing Templates ─────────────────────────────────────────────────────────
mainterm_template = Admin::StaffingTemplate.find_or_initialize_by(name: "Standard Mainterm")
if mainterm_template.new_record?
  mainterm_template.save!
  Admin::StaffingJob.create!(name: "Front of House Manager", staffable: mainterm_template)
  Admin::StaffingJob.create!(name: "Front of House", staffable: mainterm_template)
  Admin::StaffingJob.create!(name: "Front of House", staffable: mainterm_template)
  Admin::StaffingJob.create!(name: "Front of House", staffable: mainterm_template)
  Admin::StaffingJob.create!(name: "Bar Staff", staffable: mainterm_template)
  Admin::StaffingJob.create!(name: "Sound Operator", staffable: mainterm_template)
  Admin::StaffingJob.create!(name: "Lighting Operator", staffable: mainterm_template)
end

lunchtime_template = Admin::StaffingTemplate.find_or_initialize_by(name: "Lunchtime / Teatime")
if lunchtime_template.new_record?
  lunchtime_template.save!
  Admin::StaffingJob.create!(name: "Front of House Manager", staffable: lunchtime_template)
  Admin::StaffingJob.create!(name: "Front of House", staffable: lunchtime_template)
  Admin::StaffingJob.create!(name: "Front of House", staffable: lunchtime_template)
  Admin::StaffingJob.create!(name: "Tech Operator", staffable: lunchtime_template)
end

# ── Helper ─────────────────────────────────────────────────────────────────────
def seed_staffing(slug:, show_title:, start_time:, end_time:, jobs:)
  return if Admin::Staffing.find_by(slug: slug)

  staffing = Admin::Staffing.create!(
    show_title: show_title,
    start_time: start_time,
    end_time: end_time,
    counts_towards_debt: true,
    slug: slug
  )
  jobs.each do |name, user|
    Admin::StaffingJob.create!(name: name, staffable: staffing, user: user)
  end
end

# ── Season 1: Semester 1 2023-24 — Hamlet ─────────────────────────────────────
seed_staffing(
  slug: "hamlet-opening-night-staffing",
  show_title: "Hamlet - Opening Night",
  start_time: Time.zone.parse("2023-10-11 19:00"),
  end_time:   Time.zone.parse("2023-10-11 22:30"),
  jobs: [
    [ "Front of House Manager", chloe ],
    [ "Front of House", alice ],
    [ "Front of House", nil ],
    [ "Front of House", nil ],
    [ "Bar Staff", nil ],
    [ "Sound Operator", ben ],
    [ "Lighting Operator", emma ]
  ]
)

seed_staffing(
  slug: "hamlet-closing-night-staffing",
  show_title: "Hamlet - Closing Night",
  start_time: Time.zone.parse("2023-10-21 19:00"),
  end_time:   Time.zone.parse("2023-10-21 23:00"),
  jobs: [
    [ "Front of House Manager", grace ],
    [ "Front of House", finn ],
    [ "Front of House", isla ],
    [ "Front of House", nil ],
    [ "Bar Staff", nil ],
    [ "Sound Operator", nil ],
    [ "Lighting Operator", ben ]
  ]
)

# ── Season 2: Semester 2 2023-24 — Cabaret ────────────────────────────────────
seed_staffing(
  slug: "cabaret-preview-night-staffing",
  show_title: "Cabaret - Preview Night",
  start_time: Time.zone.parse("2024-02-07 19:00"),
  end_time:   Time.zone.parse("2024-02-07 22:30"),
  jobs: [
    [ "Front of House Manager", harry ],
    [ "Front of House", isla ],
    [ "Front of House", nil ],
    [ "Front of House", nil ],
    [ "Bar Staff", grace ],
    [ "Sound Operator", ben ],
    [ "Lighting Operator", emma ]
  ]
)

seed_staffing(
  slug: "cabaret-closing-night-staffing",
  show_title: "Cabaret - Closing Night",
  start_time: Time.zone.parse("2024-02-17 19:00"),
  end_time:   Time.zone.parse("2024-02-17 23:00"),
  jobs: [
    [ "Front of House Manager", alice ],
    [ "Front of House", finn ],
    [ "Front of House", nil ],
    [ "Front of House", nil ],
    [ "Bar Staff", nil ],
    [ "Sound Operator", nil ],
    [ "Lighting Operator", david ]
  ]
)

seed_staffing(
  slug: "tea-at-five-staffing",
  show_title: "Tea at Five",
  start_time: Time.zone.parse("2024-03-13 19:00"),
  end_time:   Time.zone.parse("2024-03-13 21:00"),
  jobs: [
    [ "Front of House Manager", david ],
    [ "Front of House", grace ],
    [ "Front of House", nil ],
    [ "Tech Operator", finn ]
  ]
)

# ── Season 3: Semester 1 2024-25 — A Midsummer Night's Dream ──────────────────
seed_staffing(
  slug: "midsummer-opening-night-staffing",
  show_title: "A Midsummer Night's Dream - Opening Night",
  start_time: Time.zone.parse("2024-10-09 19:00"),
  end_time:   Time.zone.parse("2024-10-09 22:30"),
  jobs: [
    [ "Front of House Manager", isla ],
    [ "Front of House", alice ],
    [ "Front of House", ben ],
    [ "Front of House", nil ],
    [ "Bar Staff", grace ],
    [ "Sound Operator", nil ],
    [ "Lighting Operator", emma ]
  ]
)

seed_staffing(
  slug: "midsummer-closing-night-staffing",
  show_title: "A Midsummer Night's Dream - Closing Night",
  start_time: Time.zone.parse("2024-10-19 19:00"),
  end_time:   Time.zone.parse("2024-10-19 23:00"),
  jobs: [
    [ "Front of House Manager", chloe ],
    [ "Front of House", finn ],
    [ "Front of House", nil ],
    [ "Front of House", nil ],
    [ "Bar Staff", nil ],
    [ "Sound Operator", david ],
    [ "Lighting Operator", nil ]
  ]
)

seed_staffing(
  slug: "importance-earnest-staffing",
  show_title: "The Importance of Being Earnest",
  start_time: Time.zone.parse("2024-11-20 19:00"),
  end_time:   Time.zone.parse("2024-11-20 21:30"),
  jobs: [
    [ "Front of House Manager", harry ],
    [ "Front of House", alice ],
    [ "Front of House", nil ],
    [ "Tech Operator", ben ]
  ]
)

# ── Season 4: Semester 2 2024-25 — Rent ───────────────────────────────────────
if Admin::Staffing.find_by(slug: "rent-preview-night-staffing").nil?
  staffing = Admin::Staffing.create!(
    show_title: "Rent - Preview Night",
    start_time: Time.zone.parse("2025-02-05 19:00"),
    end_time: Time.zone.parse("2025-02-05 22:30"),
    counts_towards_debt: true,
    slug: "rent-preview-night-staffing"
  )
  Admin::StaffingJob.create!(name: "Front of House Manager", staffable: staffing)
  Admin::StaffingJob.create!(name: "Front of House", staffable: staffing)
  Admin::StaffingJob.create!(name: "Front of House", staffable: staffing)
  Admin::StaffingJob.create!(name: "Sound Operator", staffable: staffing, user: ben)
  Admin::StaffingJob.create!(name: "Lighting Operator", staffable: staffing, user: alice)
end

if Admin::Staffing.find_by(slug: "rent-closing-night-staffing").nil?
  staffing2 = Admin::Staffing.create!(
    show_title: "Rent - Closing Night",
    start_time: Time.zone.parse("2025-02-15 19:00"),
    end_time: Time.zone.parse("2025-02-15 23:00"),
    counts_towards_debt: true,
    slug: "rent-closing-night-staffing"
  )
  Admin::StaffingJob.create!(name: "Front of House Manager", staffable: staffing2)
  Admin::StaffingJob.create!(name: "Front of House", staffable: staffing2)
  Admin::StaffingJob.create!(name: "Front of House", staffable: staffing2)
  Admin::StaffingJob.create!(name: "Bar Staff", staffable: staffing2)
end

if Admin::Staffing.find_by(slug: "new-writing-festival-2025-staffing").nil?
  staffing3 = Admin::Staffing.create!(
    show_title: "New Writing Festival 2025",
    start_time: Time.zone.parse("2025-03-12 19:00"),
    end_time: Time.zone.parse("2025-03-12 22:00"),
    counts_towards_debt: true,
    slug: "new-writing-festival-2025-staffing"
  )
  Admin::StaffingJob.create!(name: "Front of House Manager", staffable: staffing3)
  Admin::StaffingJob.create!(name: "Front of House", staffable: staffing3)
  Admin::StaffingJob.create!(name: "Tech Operator", staffable: staffing3)
end

# ── Upcoming: Semester 1 2025-26 (future placeholder) ─────────────────────────
seed_staffing(
  slug: "semester-1-2025-26-mainterm-opening-staffing",
  show_title: "Semester 1 2025-26 Mainterm - Opening Night",
  start_time: Time.zone.parse("2025-10-15 19:00"),
  end_time:   Time.zone.parse("2025-10-15 22:30"),
  jobs: [
    [ "Front of House Manager", nil ],
    [ "Front of House", nil ],
    [ "Front of House", nil ],
    [ "Front of House", nil ],
    [ "Bar Staff", nil ],
    [ "Sound Operator", nil ],
    [ "Lighting Operator", nil ]
  ]
)
