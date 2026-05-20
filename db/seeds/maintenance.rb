alice = User.find_by!(email: "alice.jones@sms.ed.ac.uk")
ben = User.find_by!(email: "ben.mackenzie@sms.ed.ac.uk")
chloe = User.find_by!(email: "chloe.harvey@sms.ed.ac.uk")
david = User.find_by!(email: "david.osei@sms.ed.ac.uk")
emma = User.find_by!(email: "emma.thornton@sms.ed.ac.uk")
finn = User.find_by!(email: "finn.obrien@sms.ed.ac.uk")
grace = User.find_by!(email: "grace.liu@sms.ed.ac.uk")
harry = User.find_by!(email: "harry.walsh@sms.ed.ac.uk")
isla = User.find_by!(email: "isla.ferguson@sms.ed.ac.uk")

sessions_with_attendees = [
  # Semester 1 2023-24
  [ Date.new(2023, 10, 7),  [ alice, ben, chloe, david ] ],
  [ Date.new(2023, 11, 4),  [ emma, finn, grace, harry, isla ] ],
  [ Date.new(2023, 11, 25), [ alice, finn, grace, ben ] ],
  [ Date.new(2023, 12, 2),  [ chloe, david, emma, harry ] ],

  # Semester 2 2023-24
  [ Date.new(2024, 2, 3),   [ alice, ben, isla, finn, emma ] ],
  [ Date.new(2024, 3, 2),   [ grace, harry, chloe, david ] ],
  [ Date.new(2024, 3, 23),  [ ben, alice, finn, isla ] ],
  [ Date.new(2024, 4, 20),  [ emma, grace, harry, chloe, david ] ],

  # Semester 1 2024-25
  [ Date.new(2024, 9, 28),  [ alice, chloe, finn, isla ] ],
  [ Date.new(2024, 10, 12), [ ben, david, emma, grace, harry ] ],
  [ Date.new(2024, 11, 9),  [ alice, ben, chloe, finn ] ],
  [ Date.new(2024, 12, 7),  [ emma, grace, harry, isla ] ],

  # Semester 2 2024-25 (already partially seeded, use find_or_create_by throughout)
  [ Date.new(2025, 1, 18),  [ alice, ben, david, finn ] ],
  [ Date.new(2025, 2, 22),  [ chloe, emma, grace, harry, isla ] ],
  [ Date.new(2025, 3, 29),  [ alice, ben, chloe, david, finn ] ]
]

sessions_with_attendees.each do |date, attendees|
  session = MaintenanceSession.find_or_create_by(date: date)
  attendees.each do |user|
    MaintenanceAttendance.find_or_create_by(maintenance_session: session, user: user)
  end
end
