find_or_seed(Venue, { name: "Bedlam Theatre" }, {
  description: "Student-run theatre in the heart of Edinburgh's Old Town.",
  location: "55.946324, -3.190721",
  address: "11b Bristo Place, EH1 1EZ",
  tagline: "Edinburgh's only student-run theatre"
})

find_or_seed(Venue, { name: "Pleasance Theatre" }, {
  description: "A large multi-space venue at Pleasance Courtyard.",
  location: "55.94753901949639, -3.1815457437588446",
  tagline: "Part of the Pleasance complex"
})

find_or_seed(Venue, { name: "Roxy Central" }, {
  description: "Nice but expensive.",
  location: "",
  tagline: "Roxy Arts Centre"
})

find_or_seed(Venue, { name: "Unknown" }, {
  description: "For when the venue isn't known yet.",
  tagline: "Venue TBC"
})
