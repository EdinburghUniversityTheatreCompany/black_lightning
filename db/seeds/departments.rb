[
  { name: "Acting",           ordering: 0,  match_terms: "actor, acting, cast" },
  { name: "Directing",        ordering: 1,  match_terms: "director, directing, assistant director" },
  { name: "Stage Management", ordering: 2,  match_terms: "stage manager, sm, asm, stage management, deputy stage" },
  { name: "Lighting",         ordering: 3,  match_terms: "light, lx, lighting" },
  { name: "Sound",            ordering: 4,  match_terms: "sound, sfx, audio" },
  { name: "Set",              ordering: 5,  match_terms: "set, scenic, build" },
  { name: "Costume",          ordering: 6,  match_terms: "costume, wardrobe" },
  { name: "Writing",          ordering: 7,  match_terms: "writer, playwright, writing, script" },
  { name: "Production",       ordering: 8,  match_terms: "producer, production" },
  { name: "Marketing",        ordering: 9,  match_terms: "marketing, publicity, social media" },
  { name: "Front of House",   ordering: 10, match_terms: "front of house, foh, usher, box office" },
  { name: "Other",            ordering: 11, match_terms: "" }
].each do |attrs|
  find_or_seed(Department, { name: attrs[:name] }, attrs.except(:name))
end
