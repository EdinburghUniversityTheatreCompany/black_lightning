[ "Member", "Committee", "Admin", "Welfare Contact", "Bar Trained", "DM Trained", "First Aid Trained", "Tool Trained", "Life Member" ].each do |name|
  find_or_seed(Group, { name: name })
end
