alice = User.find_by!(email: "alice.jones@sms.ed.ac.uk")
ben = User.find_by!(email: "ben.mackenzie@sms.ed.ac.uk")
chloe = User.find_by!(email: "chloe.harvey@sms.ed.ac.uk")
david = User.find_by!(email: "david.osei@sms.ed.ac.uk")
emma = User.find_by!(email: "emma.thornton@sms.ed.ac.uk")
finn = User.find_by!(email: "finn.obrien@sms.ed.ac.uk")

[
  {
    item: "Stage Left Wing Flat",
    description: "The flat in the stage left wing has a crack running along the bottom join. It's stable but needs repainting and a bit of filler.",
    severity: :annoying,
    status: :reported,
    reported_by: alice
  },
  {
    item: "FOH Desk Lamp",
    description: "The lamp at the front of house desk is flickering. Probably needs a new bulb.",
    severity: :annoying,
    status: :completed,
    reported_by: ben,
    fixed_by: emma
  },
  {
    item: "Dimmer Rack Channel 7",
    description: "Channel 7 on the main dimmer rack is not responding. LX cannot use this circuit until repaired.",
    severity: :show_impeding,
    status: :in_progress,
    reported_by: ben
  },
  {
    item: "Trap Door Hinge",
    description: "The stage trap door hinge is loose and squeaks loudly when opened. Needs to be tightened before next show.",
    severity: :probably_worth_fixing,
    status: :on_hold,
    reported_by: chloe
  },
  {
    item: "Fire Exit Sign (Stage Right)",
    description: "The illuminated fire exit sign above the stage right exit has stopped lighting up. This is a safety issue.",
    severity: :dangerous,
    status: :completed,
    reported_by: david,
    fixed_by: finn
  },
  {
    item: "Green Room Sink",
    description: "The hot tap in the green room drips constantly. Wastes water and is annoying.",
    severity: :annoying,
    status: :wont_fix,
    reported_by: emma
  },
  {
    item: "Spot Bar Rigging Point",
    description: "The upstage rigging point for the spot bar is showing some wear on the shackle pin. Needs inspection.",
    severity: :show_impeding,
    status: :reported,
    reported_by: ben
  },
  {
    item: "Prompt Corner Headset",
    description: "The headset at prompt corner cuts in and out. Hard to run a show without a reliable comms link.",
    severity: :probably_worth_fixing,
    status: :in_progress,
    reported_by: alice
  }
].each do |attrs|
  next if FaultReport.where(item: attrs[:item], reported_by: attrs[:reported_by]).exists?

  FaultReport.create!(attrs)
end
