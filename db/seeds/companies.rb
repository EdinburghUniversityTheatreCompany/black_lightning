[
  { name: "Edinburgh University Theatre Company", internal: true, website: "https://bedlamtheatre.co.uk" },
  { name: "Gutter Theatre", internal: false, website: "https://example.com/gutter" },
  { name: "Theatre Paradok", internal: false }
].each do |attrs|
  find_or_seed(Company, { name: attrs[:name] }, attrs.except(:name))
end
