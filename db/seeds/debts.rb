alice, ben, chloe, david, finn, grace, harry =
  seed_demo_users.values_at(:alice, :ben, :chloe, :david, :finn, :grace, :harry)

hamlet  = Show.find_by(slug: "hamlet")
cabaret = Show.find_by(slug: "cabaret")
rent    = Show.find_by(slug: "rent")
midsummer = Show.find_by(slug: "a-midsummer-nights-dream")

staffing_debts = [
  { user: alice,  show: hamlet,  due_by: Date.new(2023, 10, 21), state: :forgiven },
  { user: ben,    show: cabaret, due_by: Date.new(2024, 2, 17),  state: :forgiven },
  { user: finn,   show: midsummer, due_by: Date.new(2024, 10, 20), state: :normal },
  { user: chloe,  show: rent, due_by: Date.new(2025, 8, 1), state: :normal },
  { user: david,  show: rent, due_by: Date.new(2025, 8, 1), state: :normal },
  { user: harry,  show: rent, due_by: Date.new(2025, 8, 1), state: :normal },
  { user: grace,  show: rent, due_by: Date.new(2025, 9, 1), state: :normal, converted_from_maintenance_debt: true }
]

staffing_debts.each do |attrs|
  next unless attrs[:show]
  next if Admin::StaffingDebt.where(user: attrs[:user], show: attrs[:show], state: attrs[:state]).exists?

  Admin::StaffingDebt.create!(attrs)
end

maintenance_debts = [
  { user: alice,  show: hamlet,    due_by: Date.new(2023, 12, 1),  state: :normal },
  { user: ben,    show: cabaret,   due_by: Date.new(2024, 4, 1),   state: :forgiven },
  { user: david,  show: midsummer, due_by: Date.new(2024, 12, 1),  state: :normal },
  { user: chloe,  show: rent,      due_by: Date.new(2025, 9, 1),   state: :normal },
  { user: finn,   show: rent,      due_by: Date.new(2025, 9, 1),   state: :normal },
  { user: harry,  show: rent,      due_by: Date.new(2025, 9, 1),   state: :normal },
  { user: grace,  show: rent,      due_by: Date.new(2025, 10, 1),  state: :normal, converted_from_staffing_debt: true }
]

maintenance_debts.each do |attrs|
  next unless attrs[:show]
  next if Admin::MaintenanceDebt.where(user: attrs[:user], show: attrs[:show], state: attrs[:state]).exists?

  debt = Admin::MaintenanceDebt.create!(attrs)

  if attrs[:user] == alice && attrs[:show] == hamlet
    credit = MaintenanceCredit.find_by(user: alice)
    debt.update_column(:maintenance_credit_id, credit.id) if credit
  end
end
