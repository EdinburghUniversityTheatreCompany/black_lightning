# Techie family tree — a small set of entries representing DM training lineage.
# Parents trained their children in the DM role.

def seed_techie(name, entry_year: nil)
  Techie.find_or_create_by(name: name) do |t|
    t.entry_year = entry_year
  end
end

# Generation 1 — founding techies
alice_t  = seed_techie("Alice Hawthorne", entry_year: 2019)
bob_t    = seed_techie("Bob Fenwick",     entry_year: 2019)

# Generation 2 — trained by Gen 1
chloe_t  = seed_techie("Chloe Ramsay",   entry_year: 2021)
dan_t    = seed_techie("Dan Okonkwo",     entry_year: 2021)
eve_t    = seed_techie("Eve Sinclair",    entry_year: 2022)

# Generation 3 — trained by Gen 2
finn_t   = seed_techie("Finn Delaney",    entry_year: 2023)
grace_t  = seed_techie("Grace Muir",      entry_year: 2023)
harry_t  = seed_techie("Harry Baird",     entry_year: 2024)

# Establish parent → child relationships
{
  alice_t  => [ chloe_t, dan_t ],
  bob_t    => [ eve_t ],
  chloe_t  => [ finn_t, grace_t ],
  dan_t    => [ harry_t ]
}.each do |parent, children|
  children.each do |child|
    parent.children << child unless parent.children.include?(child)
  end
end
