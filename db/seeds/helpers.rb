def find_or_seed(klass, find_attrs, other_attrs = {})
  record = klass.find_or_initialize_by(find_attrs)
  record.assign_attributes(other_attrs) if record.new_record?
  record.save!
  record
end

def seed_puts(msg)
  puts "  [seed] #{msg}"
end
