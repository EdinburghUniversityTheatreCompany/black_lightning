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
editable_blocks = [
  # ── Main public pages ──────────────────────────────────────────────────────
  {
    url: "about",
    name: "About",
    group: "About",
    admin_page: false,
    ordering: 1,
    content: "Bedlam Theatre is the home of the Edinburgh University Theatre Company (EUTC). We are a student-run theatre based in the heart of Edinburgh."
  },
  {
    url: "about/our-story",
    name: "Our Story",
    group: "About",
    admin_page: false,
    ordering: 2,
    content: "Placeholder content for Our Story."
  },
  {
    url: "about/contact",
    name: "Contact Us",
    group: "About",
    admin_page: false,
    ordering: 3,
    content: "Placeholder content for Contact Us."
  },
  {
    url: "get_involved",
    name: "Get Involved",
    group: "Get Involved",
    admin_page: false,
    ordering: 1,
    content: "There are lots of ways to get involved at Bedlam — on stage, backstage, front of house, and more."
  },
  {
    url: "get_involved/shows",
    name: "Get Involved in Shows",
    group: "Get Involved",
    admin_page: false,
    ordering: 2,
    content: "Placeholder content for getting involved in shows."
  },
  {
    url: "get_involved/backstage",
    name: "Backstage & Tech",
    group: "Get Involved",
    admin_page: false,
    ordering: 3,
    content: "Placeholder content for backstage and tech roles."
  },
  {
    url: "get_involved/welcome_week",
    name: "Welcome Week",
    group: "Get Involved",
    admin_page: false,
    ordering: 4,
    content: "Placeholder content for Welcome Week."
  },
  {
    url: "get_involved/fringe",
    name: "Edinburgh Fringe",
    group: "Get Involved",
    admin_page: false,
    ordering: 5,
    content: "Placeholder content for Edinburgh Fringe."
  },
  {
    url: "get_involved/opportunities",
    name: "Opportunities",
    group: "Get Involved",
    admin_page: false,
    ordering: 6,
    content: "External opportunities for EUTC members — auditions, crew calls, and more from around Edinburgh."
  },
  # ── Admin pages ────────────────────────────────────────────────────────────
  {
    url: "admin/resources",
    name: "Resources",
    group: "Resources",
    admin_page: true,
    ordering: 1,
    content: "Useful resources and links for EUTC members and committee."
  },
  {
    url: "admin/resources/membership_checker",
    name: "Membership Checker",
    group: "Resources",
    admin_page: true,
    ordering: 2,
    content: "Use the form below to check whether someone is a current EUTC member."
  },
  # ── Special blocks (looked up by name, no URL) ─────────────────────────────
  {
    url: nil,
    name: "No Opportunities",
    group: "Get Involved",
    admin_page: false,
    ordering: nil,
    content: "There are no opportunities listed right now. Check back soon, or [submit your own](/get_involved/opportunities/new)."
  }
]

editable_blocks.each do |attrs|
  block = Admin::EditableBlock.find_or_initialize_by(name: attrs[:name])
  block.assign_attributes(attrs)
  block.save!
end

# ── Carousel Items ─────────────────────────────────────────────────────────────
carousel_items = [
  {
    title: "Welcome to Bedlam Theatre",
    tagline: "Edinburgh's student theatre, run entirely by students since 1986.",
    carousel_name: "Home",
    ordering: 1,
    is_active: true,
    url: "/about",
    image_path: Rails.root.join("app/assets/images/Header.jpg"),
    image_filename: "header.jpg",
    image_content_type: "image/jpeg"
  },
  {
    title: "See Our Shows",
    tagline: "From Shakespeare to brand-new writing — there's always something on at Bedlam.",
    carousel_name: "Home",
    ordering: 2,
    is_active: true,
    url: "/shows",
    image_path: Rails.root.join("app/assets/images/card_background.jpg"),
    image_filename: "card_background.jpg",
    image_content_type: "image/jpeg"
  },
  {
    title: "Get Involved",
    tagline: "Act, direct, design, build, or run the bar — everyone is welcome.",
    carousel_name: "Home",
    ordering: 3,
    is_active: true,
    url: "/get_involved",
    image_path: Rails.root.join("app/assets/images/Header.jpg"),
    image_filename: "header2.jpg",
    image_content_type: "image/jpeg"
  }
]

carousel_items.each do |attrs|
  image_path = attrs.delete(:image_path)
  image_filename = attrs.delete(:image_filename)
  image_content_type = attrs.delete(:image_content_type)

  item = CarouselItem.find_or_initialize_by(title: attrs[:title])
  item.assign_attributes(attrs)

  unless item.image.attached?
    item.image.attach(
      io: File.open(image_path),
      filename: image_filename,
      content_type: image_content_type
    )
  end

  item.save!
end
