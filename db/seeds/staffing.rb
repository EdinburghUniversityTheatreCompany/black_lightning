alice = User.find_by!(email: "alice.jones@sms.ed.ac.uk")
ben = User.find_by!(email: "ben.mackenzie@sms.ed.ac.uk")

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
