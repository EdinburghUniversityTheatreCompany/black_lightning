def find_or_seed(klass, find_attrs, other_attrs = {})
  record = klass.find_or_initialize_by(find_attrs)
  record.assign_attributes(other_attrs) if record.new_record?
  record.save!
  record
end

def seed_puts(msg)
  puts "  [seed] #{msg}"
end

# Demo users shared across several seed files (events, staffing, maintenance).
# Returns a hash keyed by first name so callers can pull just the ones they need:
#   alice, ben = seed_demo_users.values_at(:alice, :ben)
def seed_demo_users
  {
    alice: "alice.jones@sms.ed.ac.uk",
    ben:   "ben.mackenzie@sms.ed.ac.uk",
    chloe: "chloe.harvey@sms.ed.ac.uk",
    david: "david.osei@sms.ed.ac.uk",
    emma:  "emma.thornton@sms.ed.ac.uk",
    finn:  "finn.obrien@sms.ed.ac.uk",
    grace: "grace.liu@sms.ed.ac.uk",
    harry: "harry.walsh@sms.ed.ac.uk",
    isla:  "isla.ferguson@sms.ed.ac.uk"
  }.transform_values { |email| User.find_by!(email: email) }
end
