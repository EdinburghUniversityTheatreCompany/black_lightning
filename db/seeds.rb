require_relative "seeds/helpers"

seed_files = %w[
  roles
  venues
  event_tags
  users
  events
  staffing
  maintenance
  proposals
  questionnaires
  fault_reports
  techies
  content
  media
  debts
]

seed_files.each do |file|
  puts "Seeding #{file}..."
  require_relative "seeds/#{file}"
end
