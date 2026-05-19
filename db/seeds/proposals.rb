alice = User.find_by!(email: "alice.jones@sms.ed.ac.uk")
chloe = User.find_by!(email: "chloe.harvey@sms.ed.ac.uk")
harry = User.find_by!(email: "harry.walsh@sms.ed.ac.uk")

call = Admin::Proposals::Call.find_or_initialize_by(name: "Semester 1 2025-26 Proposals")
if call.new_record?
  call.assign_attributes(
    submission_deadline: Date.new(2025, 6, 1),
    editing_deadline: Date.new(2025, 5, 25),
    archived: false
  )
  call.save!
end

[
  {
    show_title: "Othello",
    proposal_text: "A fresh take on Shakespeare's tragedy of jealousy and race, set in a contemporary Edinburgh context.",
    publicity_text: "Iago plants the seeds of doubt in a general's mind with devastating consequences.",
    status: :awaiting_approval,
    user: chloe
  },
  {
    show_title: "The Monstrous Heart (New Writing)",
    proposal_text: "An original two-hander exploring grief through folk horror. Two sisters, one secret, no escape.",
    publicity_text: "When two sisters return to their childhood home they uncover a terrible secret.",
    status: :approved,
    user: alice
  },
  {
    show_title: "Chicago",
    proposal_text: "The classic Kander & Ebb musical about celebrity, corruption and showbiz. Perfect for a large Bedlam cast.",
    publicity_text: "Razzle dazzle 'em.",
    status: :awaiting_approval,
    user: harry
  }
].each do |attrs|
  user = attrs.delete(:user)
  proposal = Admin::Proposals::Proposal.find_or_initialize_by(show_title: attrs[:show_title], call: call)
  if proposal.new_record?
    proposal.assign_attributes(attrs)
    proposal.save!
    TeamMember.find_or_create_by(user: user, teamwork: proposal) do |tm|
      tm.position = "Director"
    end
  end
end
