alice, chloe, harry = seed_demo_users.values_at(:alice, :chloe, :harry)

proposal_questions = [
  [ "Why do you want to put on this show?", "Long Text" ],
  [ "What is your directorial vision?", "Long Text" ],
  [ "What is your estimated budget?", "Short Text" ],
  [ "Have you directed at Bedlam before?", "Yes/No" ]
]

# Proposal call question template
standard_template = Admin::Proposals::CallQuestionTemplate.find_or_initialize_by(name: "Standard Proposal Questions")
if standard_template.new_record?
  standard_template.save!
  seed_questions(standard_template, proposal_questions)
end

# Active proposal call
call = Admin::Proposals::Call.find_or_initialize_by(name: "Semester 1 2025-26 Proposals")
if call.new_record?
  call.assign_attributes(
    submission_deadline: Date.new(2025, 6, 1),
    editing_deadline: Date.new(2025, 5, 25),
    archived: false
  )
  call.save!
  seed_questions(call, proposal_questions)
end

# Archived call from previous semester
archived_call = Admin::Proposals::Call.find_or_initialize_by(name: "Semester 2 2024-25 Proposals")
if archived_call.new_record?
  archived_call.assign_attributes(
    submission_deadline: Date.new(2024, 12, 1),
    editing_deadline: Date.new(2024, 11, 25),
    archived: true
  )
  archived_call.save!
  seed_questions(archived_call, proposal_questions.first(2))
end

# Proposals for active call
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
  proposal = find_or_seed(Admin::Proposals::Proposal, { show_title: attrs[:show_title], call: call }, attrs)
  TeamMember.find_or_create_by(user: user, teamwork: proposal) do |tm|
    tm.position = "Director"
  end
end
