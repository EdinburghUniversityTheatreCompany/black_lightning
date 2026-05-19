[
  Date.new(2024, 10, 12),
  Date.new(2024, 11, 9),
  Date.new(2025, 1, 18),
  Date.new(2025, 2, 22),
  Date.new(2025, 3, 29)
].each do |date|
  MaintenanceSession.find_or_create_by(date: date)
end
