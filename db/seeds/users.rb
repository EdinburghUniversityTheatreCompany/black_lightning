def seed_user(email, first_name, last_name, roles: [], **attrs)
  user = User.find_or_initialize_by(email: email)
  if user.new_record?
    user.assign_attributes(
      first_name: first_name,
      last_name: last_name,
      password: "Passw0rd",
      password_confirmation: "Passw0rd",
      consented: 1.year.ago,
      profile_completed_at: 1.year.ago,
      **attrs
    )
    user.save!
    roles.each { |role| user.add_role(role) }
    seed_puts "Created #{email}"
  end
  user
end

# Admin
seed_user("admin@bedlamtheatre.co.uk", "Alice", "Admin", roles: [ :admin ])

# Committee members
seed_user("president@bedlamtheatre.co.uk", "Patrick", "Brennan",
  roles: [ :member, "Committee" ], bio: "Current EUTC President.")
seed_user("secretary@bedlamtheatre.co.uk", "Sarah", "Chambers",
  roles: [ :member, "Committee" ], bio: "Secretary and archivist.")
seed_user("treasurer@bedlamtheatre.co.uk", "Tom", "Whitfield",
  roles: [ :member, "Committee" ], bio: "Treasurer keeping the books balanced.")
seed_user("techmanager@bedlamtheatre.co.uk", "Maya", "Patel",
  roles: [ :member, "Committee", "DM Trained", "First Aid Trained" ],
  bio: "Tech manager and resident lighting designer.")
seed_user("welfare@bedlamtheatre.co.uk", "Jamie", "Ellis",
  roles: [ :member, "Committee", "Welfare Contact" ],
  bio: "Welfare and equalities officer.")

# Regular members
seed_user("alice.jones@sms.ed.ac.uk", "Alice", "Jones",
  roles: [ :member ], bio: "Actress and stage manager.")
seed_user("ben.mackenzie@sms.ed.ac.uk", "Ben", "MacKenzie",
  roles: [ :member, "DM Trained", "Bar Trained" ])
seed_user("chloe.harvey@sms.ed.ac.uk", "Chloe", "Harvey",
  roles: [ :member ], bio: "Director and writer.")
seed_user("david.osei@sms.ed.ac.uk", "David", "Osei",
  roles: [ :member, "First Aid Trained" ])
seed_user("emma.thornton@sms.ed.ac.uk", "Emma", "Thornton",
  roles: [ :member, "Tool Trained" ])
seed_user("finn.obrien@sms.ed.ac.uk", "Finn", "O'Brien",
  roles: [ :member ], bio: "Set designer and builder.")
seed_user("grace.liu@sms.ed.ac.uk", "Grace", "Liu",
  roles: [ :member, "Bar Trained" ])
seed_user("harry.walsh@sms.ed.ac.uk", "Harry", "Walsh",
  roles: [ :member ])
seed_user("isla.ferguson@sms.ed.ac.uk", "Isla", "Ferguson",
  roles: [ :member ], bio: "Costume designer and wardrobe mistress.")

# Life member
seed_user("life@bedlamtheatre.co.uk", "Leslie", "Oldmember",
  roles: [ :"life member" ])

# Claude Code dev testing user
claude_user = User.find_or_initialize_by(email: "unknown_claude@bedlamtheatre.co.uk")
if claude_user.new_record?
  claude_user.assign_attributes(
    password: SecureRandom.hex(20),
    first_name: "Claude", last_name: "Dev",
    consented: Time.current, profile_completed_at: Time.current
  )
  claude_user.save!
  claude_user.add_role(:admin)
  seed_puts "Created unknown_claude@bedlamtheatre.co.uk"
end
