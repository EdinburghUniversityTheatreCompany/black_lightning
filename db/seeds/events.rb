bedlam = Venue.find_by!(name: "Bedlam Theatre")
mainterm_tag = EventTag.find_by!(name: "Mainterm.")
lunchtime_tag = EventTag.find_by!(name: "Lunchtime")
new_writing_tag = EventTag.find_by!(name: "New Writing")
musical_tag = EventTag.find_by!(name: "Musical")
teatime_tag = EventTag.find_by!(name: "Teatime")

alice = User.find_by!(email: "alice.jones@sms.ed.ac.uk")
ben = User.find_by!(email: "ben.mackenzie@sms.ed.ac.uk")
chloe = User.find_by!(email: "chloe.harvey@sms.ed.ac.uk")
david = User.find_by!(email: "david.osei@sms.ed.ac.uk")
emma = User.find_by!(email: "emma.thornton@sms.ed.ac.uk")
finn = User.find_by!(email: "finn.obrien@sms.ed.ac.uk")
grace = User.find_by!(email: "grace.liu@sms.ed.ac.uk")
harry = User.find_by!(email: "harry.walsh@sms.ed.ac.uk")
isla = User.find_by!(email: "isla.ferguson@sms.ed.ac.uk")

def seed_season(name:, start_date:, end_date:, venue:)
  season = Season.find_or_initialize_by(slug: name.to_url)
  if season.new_record?
    season.assign_attributes(
      name: name, start_date: start_date, end_date: end_date, venue: venue, is_public: true,
      publicity_text: "#{name} at Bedlam Theatre.",
      members_only_text: "Members-only information for #{name} will be added here."
    )
    season.save!
  end
  season
end

def seed_show(name:, author:, season:, venue:, start_date:, end_date:, tagline:,
              publicity_text:, price:, tags: [], team: [], is_public: true)
  show = Show.find_or_initialize_by(slug: name.to_url)
  if show.new_record?
    show.assign_attributes(
      name: name, author: author, season: season, venue: venue,
      start_date: start_date, end_date: end_date, tagline: tagline,
      publicity_text: publicity_text, members_only_text: "Members-only information will be added here.", price: price, is_public: is_public
    )
    show.save!
    show.event_tags = tags
    team.each do |user, position|
      TeamMember.find_or_create_by(user: user, teamwork: show) do |tm|
        tm.position = position
      end
    end
  end
  show
end

def seed_workshop(name:, season:, venue:, start_date:, end_date:, tagline:, is_public: true)
  workshop = Workshop.find_or_initialize_by(slug: name.to_url)
  if workshop.new_record?
    workshop.assign_attributes(
      name: name, season: season, venue: venue,
      start_date: start_date, end_date: end_date, tagline: tagline, is_public: is_public,
      publicity_text: tagline,
      members_only_text: "Members-only information will be added here."
    )
    workshop.save!
  end
  workshop
end

# ── Season 1: Semester 1 2023-24 ──────────────────────────────────────────────
s1 = seed_season(
  name: "Semester 1 2023-24",
  start_date: Date.new(2023, 9, 18),
  end_date: Date.new(2023, 12, 10),
  venue: bedlam
)

hamlet = seed_show(
  name: "Hamlet", author: "William Shakespeare", season: s1, venue: bedlam,
  start_date: Date.new(2023, 10, 11), end_date: Date.new(2023, 10, 21),
  tagline: "To be, or not to be — performed in the round.",
  publicity_text: "Bedlam's bold take on Shakespeare's greatest tragedy, staged in full traverse.",
  price: "£8 / £6 concessions",
  tags: [ mainterm_tag ],
  team: [ [ chloe, "Director" ], [ alice, "Stage Manager" ], [ ben, "Lighting Designer" ],
         [ finn, "Set Designer" ], [ isla, "Costume Designer" ] ]
)

seed_show(
  name: "Lunchtime Scratch Night", author: "Various Authors", season: s1, venue: bedlam,
  start_date: Date.new(2023, 11, 1), end_date: Date.new(2023, 11, 1),
  tagline: "Short new works from emerging Bedlam writers.",
  publicity_text: "Five ten-minute plays performed over lunch — free entry, donations welcome.",
  price: "Free / donations",
  tags: [ lunchtime_tag, new_writing_tag ],
  team: [ [ chloe, "Producer" ], [ grace, "Stage Manager" ] ]
)

seed_workshop(
  name: "Stage Management Basics", season: s1, venue: bedlam,
  start_date: Date.new(2023, 10, 5), end_date: Date.new(2023, 10, 5),
  tagline: "An introduction to running the book and calling cues."
)

# ── Season 2: Semester 2 2023-24 ──────────────────────────────────────────────
s2 = seed_season(
  name: "Semester 2 2023-24",
  start_date: Date.new(2024, 1, 15),
  end_date: Date.new(2024, 4, 28),
  venue: bedlam
)

cabaret = seed_show(
  name: "Cabaret", author: "Kander & Ebb", season: s2, venue: bedlam,
  start_date: Date.new(2024, 2, 7), end_date: Date.new(2024, 2, 17),
  tagline: "Life is a Cabaret, old chum.",
  publicity_text: "Bedlam's spectacular production of the classic musical, set in Weimar-era Berlin.",
  price: "£10 / £7 concessions",
  tags: [ mainterm_tag, musical_tag ],
  team: [ [ alice, "Director" ], [ david, "Musical Director" ], [ emma, "Choreographer" ],
         [ finn, "Set Designer" ], [ ben, "Lighting Designer" ], [ isla, "Costume Designer" ] ]
)

seed_show(
  name: "Tea at Five", author: "Matthew Lombardo", season: s2, venue: bedlam,
  start_date: Date.new(2024, 3, 13), end_date: Date.new(2024, 3, 16),
  tagline: "The private life of Katharine Hepburn.",
  publicity_text: "A one-woman show exploring the remarkable life and fierce independence of a Hollywood icon.",
  price: "£7 / £5 concessions",
  tags: [ teatime_tag ],
  team: [ [ grace, "Director" ], [ alice, "Performer" ], [ harry, "Stage Manager" ] ]
)

seed_workshop(
  name: "Movement for Performers", season: s2, venue: bedlam,
  start_date: Date.new(2024, 2, 1), end_date: Date.new(2024, 2, 1),
  tagline: "Explore physicality and spatial awareness on stage."
)

# ── Season 3: Semester 1 2024-25 ──────────────────────────────────────────────
s3 = seed_season(
  name: "Semester 1 2024-25",
  start_date: Date.new(2024, 9, 16),
  end_date: Date.new(2024, 12, 8),
  venue: bedlam
)

seed_show(
  name: "A Midsummer Night's Dream", author: "William Shakespeare", season: s3, venue: bedlam,
  start_date: Date.new(2024, 10, 9), end_date: Date.new(2024, 10, 19),
  tagline: "Love, magic, and mayhem in an enchanted forest.",
  publicity_text: "Shakespeare's most beloved comedy gets a fresh, playful Bedlam treatment.",
  price: "£9 / £6 concessions",
  tags: [ mainterm_tag ],
  team: [ [ harry, "Director" ], [ chloe, "Stage Manager" ], [ emma, "Lighting Designer" ],
         [ finn, "Set Designer" ], [ isla, "Costume Designer" ] ]
)

seed_show(
  name: "The Importance of Being Earnest", author: "Oscar Wilde", season: s3, venue: bedlam,
  start_date: Date.new(2024, 11, 20), end_date: Date.new(2024, 11, 23),
  tagline: "Bunburying and cucumber sandwiches.",
  publicity_text: "Wilde's masterpiece of comic misidentity and aristocratic wit.",
  price: "£8 / £6 concessions",
  tags: [ lunchtime_tag ],
  team: [ [ david, "Director" ], [ grace, "Stage Manager" ], [ ben, "Lighting Designer" ] ]
)

seed_workshop(
  name: "Voice and Breath for Actors", season: s3, venue: bedlam,
  start_date: Date.new(2024, 9, 26), end_date: Date.new(2024, 9, 26),
  tagline: "Unlock your vocal range and breath control."
)

# ── Season 4: Semester 2 2024-25 (current) ────────────────────────────────────
s4 = seed_season(
  name: "Semester 2 2024-25",
  start_date: Date.new(2025, 1, 13),
  end_date: Date.new(2025, 5, 4),
  venue: bedlam
)

seed_show(
  name: "Rent", author: "Jonathan Larson", season: s4, venue: bedlam,
  start_date: Date.new(2025, 2, 5), end_date: Date.new(2025, 2, 15),
  tagline: "No day but today.",
  publicity_text: "Larson's Pulitzer Prize-winning rock musical about artists in New York City fighting for their lives and dreams.",
  price: "£10 / £8 concessions",
  tags: [ mainterm_tag, musical_tag ],
  team: [ [ chloe, "Director" ], [ alice, "Musical Director" ], [ emma, "Choreographer" ],
         [ finn, "Set Designer" ], [ isla, "Costume Designer" ], [ ben, "Lighting Designer" ] ]
)

seed_show(
  name: "New Writing Festival 2025", author: "Various Bedlam Writers", season: s4, venue: bedlam,
  start_date: Date.new(2025, 3, 12), end_date: Date.new(2025, 3, 15),
  tagline: "Four short plays written and performed by EUTC members.",
  publicity_text: "The annual New Writing Festival showcases original work from Bedlam's own writers.",
  price: "£6 / £4 concessions",
  tags: [ lunchtime_tag, new_writing_tag ],
  team: [ [ harry, "Producer" ], [ grace, "Stage Manager" ] ]
)

# ── Reviews ────────────────────────────────────────────────────────────────────
if hamlet.reviews.empty?
  Review.create!(
    event: hamlet,
    reviewer: "Alex Mackintosh",
    organisation: "The Student",
    rating: 4.0,
    title: "Shakespeare in Safe Hands",
    body: "Bedlam's Hamlet is a taut, intelligent production that does full justice to the text.",
    review_date: Date.new(2023, 10, 18)
  )
end

if cabaret.reviews.empty?
  Review.create!(
    event: cabaret,
    reviewer: "Priya Shah",
    organisation: "The Edinburgh Student",
    rating: 5.0,
    title: "Dazzling, Dark, Essential",
    body: "Bedlam's Cabaret is quite simply unmissable — vital, visceral, and brilliantly performed.",
    review_date: Date.new(2024, 2, 12)
  )
end
