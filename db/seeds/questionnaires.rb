# ── Questionnaire Templates ────────────────────────────────────────────────────
post_show_template = Admin::Questionnaires::QuestionnaireTemplate.find_or_initialize_by(name: "Post-Show Debrief")
if post_show_template.new_record?
  post_show_template.save!
  Admin::Question.create!(
    questionable: post_show_template,
    question_text: "How did the run go overall?",
    response_type: "Long Text"
  )
  Admin::Question.create!(
    questionable: post_show_template,
    question_text: "Were there any significant technical issues?",
    response_type: "Long Text"
  )
  Admin::Question.create!(
    questionable: post_show_template,
    question_text: "What would you do differently?",
    response_type: "Long Text"
  )
  Admin::Question.create!(
    questionable: post_show_template,
    question_text: "Approximate audience numbers",
    response_type: "Number"
  )
end

crew_application_template = Admin::Questionnaires::QuestionnaireTemplate.find_or_initialize_by(name: "Crew Application")
if crew_application_template.new_record?
  crew_application_template.save!
  Admin::Question.create!(
    questionable: crew_application_template,
    question_text: "What role(s) are you applying for?",
    response_type: "Short Text"
  )
  Admin::Question.create!(
    questionable: crew_application_template,
    question_text: "Describe your relevant experience",
    response_type: "Long Text"
  )
  Admin::Question.create!(
    questionable: crew_application_template,
    question_text: "Are you available for the full run?",
    response_type: "Yes/No"
  )
end

# ── Questionnaires attached to shows ──────────────────────────────────────────
hamlet = Show.find_by(slug: "hamlet")
rent   = Show.find_by(slug: "rent")

# Seed a post-show debrief questionnaire (three standard questions + answers) for a show.
# No-op if the show is missing or already has a questionnaire.
seed_post_show_debrief = lambda do |show, name:, run_answer:, technical_answer:, audience_answer:|
  next unless show && Admin::Questionnaires::Questionnaire.where(event: show).none?

  q = Admin::Questionnaires::Questionnaire.create!(event: show, name: name)
  q1 = Admin::Question.create!(
    questionable: q,
    question_text: "How did the run go overall?",
    response_type: "Long Text"
  )
  q2 = Admin::Question.create!(
    questionable: q,
    question_text: "Were there any significant technical issues?",
    response_type: "Long Text"
  )
  q3 = Admin::Question.create!(
    questionable: q,
    question_text: "Approximate audience numbers",
    response_type: "Number"
  )
  Admin::Answer.create!(question: q1, answerable: q, answer: run_answer)
  Admin::Answer.create!(question: q2, answerable: q, answer: technical_answer)
  Admin::Answer.create!(question: q3, answerable: q, answer: audience_answer)
end

seed_post_show_debrief.call(
  hamlet,
  name: "Hamlet Post-Show Debrief",
  run_answer: "Really strong run. The traverse staging worked well and the cast held energy throughout.",
  technical_answer: "One lighting cue was missed on opening night but sorted by the second performance.",
  audience_answer: "~65 per night"
)

seed_post_show_debrief.call(
  rent,
  name: "Rent Post-Show Debrief",
  run_answer: "Excellent run overall. Sold out for the closing night.",
  technical_answer: "Sound mix needed adjusting after the preview — fixed by opening night.",
  audience_answer: "~90 per night, sold out closing"
)
