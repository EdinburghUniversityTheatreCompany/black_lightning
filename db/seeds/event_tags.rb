[
  { name: "Mainterm.", ordering: 1, recommended_maintenance_debts: 1, recommended_staffing_debts: 2,
    description: "One of the main type of shows. A longer run with a higher budget." },
  { name: "Teatime", ordering: 2, recommended_maintenance_debts: 1, recommended_staffing_debts: 1,
    description: "Teatime shows - shorter performances during the afternoon." },
  { name: "Lunchtime", ordering: 3, recommended_maintenance_debts: 1, recommended_staffing_debts: 1,
    description: "One of the main type of shows. A shorter run with a lower budget." },
  { name: "New Writing", ordering: 4, recommended_maintenance_debts: 1, recommended_staffing_debts: 1,
    description: "A tag used for new writing plays. Usually written by Bedlam members." },
  { name: "Musical", ordering: 5, recommended_maintenance_debts: 1, recommended_staffing_debts: 2,
    description: "Musical theatre productions." },
  { name: "Fringe", ordering: 6, recommended_maintenance_debts: 1, recommended_staffing_debts: 2,
    description: "Edinburgh Fringe Festival productions." }
].each do |attrs|
  find_or_seed(EventTag, { name: attrs[:name] }, attrs.except(:name))
end
