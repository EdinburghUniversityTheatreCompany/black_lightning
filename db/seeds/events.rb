bedlam = Venue.find_by!(name: "Bedlam Theatre")
mainterm_tag = EventTag.find_by!(name: "Mainterm.")
lunchtime_tag = EventTag.find_by!(name: "Lunchtime")
new_writing_tag = EventTag.find_by!(name: "New Writing")
musical_tag = EventTag.find_by!(name: "Musical")
teatime_tag = EventTag.find_by!(name: "Teatime")

alice, ben, chloe, david, emma, finn, grace, harry, isla =
  seed_demo_users.values_at(:alice, :ben, :chloe, :david, :emma, :finn, :grace, :harry, :isla)

def seed_event(klass, name:, tags: [], team: [], **attrs)
  event = klass.find_or_initialize_by(slug: name.to_url)
  return event unless event.new_record?

  event.update!({ name: name, is_public: true, publicity_text: "#{name} at Bedlam Theatre.",
                  members_only_text: "Members-only information will be added here." }.merge(attrs))
  event.event_tags = tags
  team.each do |user, position|
    TeamMember.find_or_create_by(user: user, teamwork: event) { |member| member.position = position }
  end
  event
end

s1 = seed_event(
  Season, name: "Semester 1 2023-24",
  start_date: Date.new(2023, 9, 18),
  end_date: Date.new(2023, 12, 10),
  venue: bedlam
)

hamlet = seed_event(
  Show, name: "Hamlet", author: "William Shakespeare", season: s1, venue: bedlam,
  start_date: Date.new(2023, 10, 11), end_date: Date.new(2023, 10, 21),
  tagline: "To be, or not to be — performed in the round.",
  publicity_text: "Bedlam's bold take on Shakespeare's greatest tragedy, staged in full traverse.",
  price: "£8 / £6 concessions",
  tags: [ mainterm_tag ],
  team: [ [ chloe, "Director" ], [ alice, "Stage Manager" ], [ ben, "Lighting Designer" ],
         [ finn, "Set Designer" ], [ isla, "Costume Designer" ] ]
)

seed_event(
  Show, name: "Lunchtime Scratch Night", author: "Various Authors", season: s1, venue: bedlam,
  start_date: Date.new(2023, 11, 1), end_date: Date.new(2023, 11, 1),
  tagline: "Short new works from emerging Bedlam writers.",
  publicity_text: "Five ten-minute plays performed over lunch — free entry, donations welcome.",
  price: "Free / donations",
  tags: [ lunchtime_tag, new_writing_tag ],
  team: [ [ chloe, "Producer" ], [ grace, "Stage Manager" ] ]
)

seed_event(
  Workshop, name: "Stage Management Basics", season: s1, venue: bedlam,
  start_date: Date.new(2023, 10, 5), end_date: Date.new(2023, 10, 5),
  tagline: "An introduction to running the book and calling cues.",
  publicity_text: "An introduction to running the book and calling cues."
)

s2 = seed_event(
  Season, name: "Semester 2 2023-24",
  start_date: Date.new(2024, 1, 15),
  end_date: Date.new(2024, 4, 28),
  venue: bedlam
)

cabaret = seed_event(
  Show, name: "Cabaret", author: "Kander & Ebb", season: s2, venue: bedlam,
  start_date: Date.new(2024, 2, 7), end_date: Date.new(2024, 2, 17),
  tagline: "Life is a Cabaret, old chum.",
  publicity_text: "Bedlam's spectacular production of the classic musical, set in Weimar-era Berlin.",
  price: "£10 / £7 concessions",
  tags: [ mainterm_tag, musical_tag ],
  team: [ [ alice, "Director" ], [ david, "Musical Director" ], [ emma, "Choreographer" ],
         [ finn, "Set Designer" ], [ ben, "Lighting Designer" ], [ isla, "Costume Designer" ] ]
)

seed_event(
  Show, name: "Tea at Five", author: "Matthew Lombardo", season: s2, venue: bedlam,
  start_date: Date.new(2024, 3, 13), end_date: Date.new(2024, 3, 16),
  tagline: "The private life of Katharine Hepburn.",
  publicity_text: "A one-woman show exploring the remarkable life and fierce independence of a Hollywood icon.",
  price: "£7 / £5 concessions",
  tags: [ teatime_tag ],
  team: [ [ grace, "Director" ], [ alice, "Performer" ], [ harry, "Stage Manager" ] ]
)

seed_event(
  Workshop, name: "Movement for Performers", season: s2, venue: bedlam,
  start_date: Date.new(2024, 2, 1), end_date: Date.new(2024, 2, 1),
  tagline: "Explore physicality and spatial awareness on stage.",
  publicity_text: "Explore physicality and spatial awareness on stage."
)

s3 = seed_event(
  Season, name: "Semester 1 2024-25",
  start_date: Date.new(2024, 9, 16),
  end_date: Date.new(2024, 12, 8),
  venue: bedlam
)

seed_event(
  Show, name: "A Midsummer Night's Dream", author: "William Shakespeare", season: s3, venue: bedlam,
  start_date: Date.new(2024, 10, 9), end_date: Date.new(2024, 10, 19),
  tagline: "Love, magic, and mayhem in an enchanted forest.",
  publicity_text: "Shakespeare's most beloved comedy gets a fresh, playful Bedlam treatment.",
  price: "£9 / £6 concessions",
  tags: [ mainterm_tag ],
  team: [ [ harry, "Director" ], [ chloe, "Stage Manager" ], [ emma, "Lighting Designer" ],
         [ finn, "Set Designer" ], [ isla, "Costume Designer" ] ]
)

seed_event(
  Show, name: "The Importance of Being Earnest", author: "Oscar Wilde", season: s3, venue: bedlam,
  start_date: Date.new(2024, 11, 20), end_date: Date.new(2024, 11, 23),
  tagline: "Bunburying and cucumber sandwiches.",
  publicity_text: "Wilde's masterpiece of comic misidentity and aristocratic wit.",
  price: "£8 / £6 concessions",
  tags: [ lunchtime_tag ],
  team: [ [ david, "Director" ], [ grace, "Stage Manager" ], [ ben, "Lighting Designer" ] ]
)

seed_event(
  Workshop, name: "Voice and Breath for Actors", season: s3, venue: bedlam,
  start_date: Date.new(2024, 9, 26), end_date: Date.new(2024, 9, 26),
  tagline: "Unlock your vocal range and breath control.",
  publicity_text: "Unlock your vocal range and breath control."
)

s4 = seed_event(
  Season, name: "Semester 2 2024-25",
  start_date: Date.new(2025, 1, 13),
  end_date: Date.new(2025, 5, 4),
  venue: bedlam
)

seed_event(
  Show, name: "Rent", author: "Jonathan Larson", season: s4, venue: bedlam,
  start_date: Date.new(2025, 2, 5), end_date: Date.new(2025, 2, 15),
  tagline: "No day but today.",
  publicity_text: "Larson's Pulitzer Prize-winning rock musical about artists in New York City fighting for their lives and dreams.",
  price: "£10 / £8 concessions",
  tags: [ mainterm_tag, musical_tag ],
  team: [ [ chloe, "Director" ], [ alice, "Musical Director" ], [ emma, "Choreographer" ],
         [ finn, "Set Designer" ], [ isla, "Costume Designer" ], [ ben, "Lighting Designer" ] ]
)

seed_event(
  Show, name: "New Writing Festival 2025", author: "Various Bedlam Writers", season: s4, venue: bedlam,
  start_date: Date.new(2025, 3, 12), end_date: Date.new(2025, 3, 15),
  tagline: "Four short plays written and performed by EUTC members.",
  publicity_text: "The annual New Writing Festival showcases original work from Bedlam's own writers.",
  price: "£6 / £4 concessions",
  tags: [ lunchtime_tag, new_writing_tag ],
  team: [ [ harry, "Producer" ], [ grace, "Stage Manager" ] ]
)

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
