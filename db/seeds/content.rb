admin = User.find_by!(email: "admin@bedlamtheatre.co.uk")

# ── News articles ──────────────────────────────────────────────────────────────
[
  {
    title: "Welcome to Semester 2 2024-25",
    slug: "welcome-semester-2-2024-25",
    body: "Welcome back to Bedlam! We have an exciting semester ahead with Rent in February and the New Writing Festival in March. Get involved!",
    publish_date: Date.new(2025, 1, 13),
    show_public: true
  },
  {
    title: "Rent Auditions Open",
    slug: "rent-auditions-open",
    body: "Auditions for Rent are now open. Prepare 16 bars of musical theatre and a short monologue. Sign up on the website.",
    publish_date: Date.new(2025, 1, 15),
    show_public: true
  },
  {
    title: "Maintenance Session This Saturday",
    slug: "maintenance-session-feb-2025",
    body: "There's a maintenance session on Saturday 22nd February. All debts will be counted! Meet at Bedlam at 10am.",
    publish_date: Date.new(2025, 2, 18),
    show_public: false
  },
  {
    title: "New Writing Festival 2025 — Call for Scripts",
    slug: "new-writing-festival-2025-call",
    body: "Submit your short plays (up to 20 minutes) for the New Writing Festival by 1st March. All EUTC members welcome to submit.",
    publish_date: Date.new(2025, 1, 25),
    show_public: true
  },
  {
    title: "AGM — All Members Invited",
    slug: "agm-2025",
    body: "The Annual General Meeting will be held on 15th April. All members are encouraged to attend and vote.",
    publish_date: Date.new(2025, 3, 20),
    show_public: false
  }
].each do |attrs|
  news = News.find_or_initialize_by(slug: attrs[:slug])
  if news.new_record?
    news.assign_attributes(attrs.merge(author: admin))
    news.save!
  end
end

# ── Opportunities ──────────────────────────────────────────────────────────────
[
  {
    title: "Fringe Venue Seeking Front of House Volunteers",
    description: "The Pleasance is looking for volunteers for the 2025 Fringe Festival. Free shows in exchange for shifts.",
    expiry_date: Date.new(2025, 7, 1),
    approved: true
  },
  {
    title: "Director Wanted for Community Youth Theatre",
    description: "Edinburgh Youth Theatre needs a director for their summer production of Oliver! Pay negotiable.",
    expiry_date: Date.new(2025, 5, 31),
    approved: true
  },
  {
    title: "Script Reading Group — New Members Welcome",
    description: "Monthly script reading group meets in the Bedlam green room. No experience needed!",
    expiry_date: Date.new(2025, 12, 31),
    approved: true
  },
  {
    title: "Lighting Technician Wanted for Touring Show",
    description: "Small touring company seeks a junior LX tech for a 3-week Scottish tour in June.",
    expiry_date: Date.new(2025, 5, 15),
    approved: false
  }
].each do |attrs|
  opportunity = Opportunity.find_or_initialize_by(title: attrs[:title])
  if opportunity.new_record?
    opportunity.assign_attributes(attrs.merge(
      creator: admin,
      approver: attrs[:approved] ? admin : nil
    ))
    opportunity.save!
  end
end

# ── Editable Blocks ────────────────────────────────────────────────────────────
[
  { url: "about", name: "About", group: "About", admin_page: false },
  { url: "get_involved", name: "Get Involved", group: "Get Involved", admin_page: false },
  { url: "get_involved/opportunities", name: "Opportunities", group: "Get Involved", admin_page: false },
  { url: "admin/resources", name: "Resources", group: "Resources", admin_page: true },
  { url: "admin/resources/membership_checker", name: "Membership Checker", group: "Resources", admin_page: true }
].each do |attrs|
  block = Admin::EditableBlock.find_or_initialize_by(url: attrs[:url])
  block.assign_attributes(attrs)
  block.save!
end
