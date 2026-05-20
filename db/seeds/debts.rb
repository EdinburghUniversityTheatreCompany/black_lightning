alice = User.find_by!(email: "alice.jones@sms.ed.ac.uk")
ben = User.find_by!(email: "ben.mackenzie@sms.ed.ac.uk")
chloe = User.find_by!(email: "chloe.harvey@sms.ed.ac.uk")
david = User.find_by!(email: "david.osei@sms.ed.ac.uk")
finn = User.find_by!(email: "finn.obrien@sms.ed.ac.uk")
grace = User.find_by!(email: "grace.liu@sms.ed.ac.uk")
harry = User.find_by!(email: "harry.walsh@sms.ed.ac.uk")

hamlet  = Show.find_by(slug: "hamlet")
cabaret = Show.find_by(slug: "cabaret")
rent    = Show.find_by(slug: "rent")
midsummer = Show.find_by(slug: "a-midsummer-nights-dream")

# ── Staffing Debts ─────────────────────────────────────────────────────────────
staffing_debts = [
  # Past debts that have been fulfilled (forgiven or expired)
  { user: alice,  show: hamlet,  due_by: Date.new(2023, 10, 21), state: :forgiven, converted_from_maintenance_debt: false },
  { user: ben,    show: cabaret, due_by: Date.new(2024, 2, 17),  state: :forgiven, converted_from_maintenance_debt: false },
  # Past debt causing debt (due date passed, no job assigned)
  { user: finn,   show: midsummer, due_by: Date.new(2024, 10, 20), state: :normal, converted_from_maintenance_debt: false },
  # Upcoming debts (not yet due)
  { user: chloe,  show: rent, due_by: Date.new(2025, 8, 1), state: :normal, converted_from_maintenance_debt: false },
  { user: david,  show: rent, due_by: Date.new(2025, 8, 1), state: :normal, converted_from_maintenance_debt: false },
  { user: harry,  show: rent, due_by: Date.new(2025, 8, 1), state: :normal, converted_from_maintenance_debt: false },
  # Converted from a maintenance debt
  { user: grace,  show: rent, due_by: Date.new(2025, 9, 1), state: :normal, converted_from_maintenance_debt: true }
]

staffing_debts.each do |attrs|
  next unless attrs[:show]
  next if Admin::StaffingDebt.where(user: attrs[:user], show: attrs[:show], state: attrs[:state]).exists?

  Admin::StaffingDebt.create!(attrs)
end

# ── Maintenance Debts ──────────────────────────────────────────────────────────
maintenance_debts = [
  # Fulfilled debt (linked to an attendance)
  { user: alice,  show: hamlet,    due_by: Date.new(2023, 12, 1),  state: :normal, converted_from_staffing_debt: false },
  { user: ben,    show: cabaret,   due_by: Date.new(2024, 4, 1),   state: :forgiven, converted_from_staffing_debt: false },
  # Causing debt (overdue, no attendance)
  { user: david,  show: midsummer, due_by: Date.new(2024, 12, 1),  state: :normal, converted_from_staffing_debt: false },
  # Upcoming
  { user: chloe,  show: rent,      due_by: Date.new(2025, 9, 1),   state: :normal, converted_from_staffing_debt: false },
  { user: finn,   show: rent,      due_by: Date.new(2025, 9, 1),   state: :normal, converted_from_staffing_debt: false },
  { user: harry,  show: rent,      due_by: Date.new(2025, 9, 1),   state: :normal, converted_from_staffing_debt: false },
  # Converted from a staffing debt
  { user: grace,  show: rent,      due_by: Date.new(2025, 10, 1),  state: :normal, converted_from_staffing_debt: true }
]

maintenance_debts.each do |attrs|
  next unless attrs[:show]
  next if Admin::MaintenanceDebt.where(user: attrs[:user], show: attrs[:show], state: attrs[:state]).exists?

  debt = Admin::MaintenanceDebt.create!(attrs)

  # Link the fulfilled debt for alice/hamlet to an attendance she has
  if attrs[:user] == alice && attrs[:show] == hamlet
    attendance = MaintenanceAttendance.find_by(user: alice)
    debt.update_column(:maintenance_attendance_id, attendance.id) if attendance
  end
end
