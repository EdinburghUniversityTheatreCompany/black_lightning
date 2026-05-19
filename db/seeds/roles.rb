[ "Member", "Committee", "Admin", "Welfare Contact", "Bar Trained", "DM Trained", "First Aid Trained", "Tool Trained" ].each do |name|
  find_or_seed(Role, { name: name })
end
