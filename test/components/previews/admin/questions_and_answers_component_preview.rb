class Admin::QuestionsAndAnswersComponentPreview < Admin::ApplicationComponentPreview
  # Questions with no answers filled in
  def unanswered
    answers = Questionnaire.joins(:answers).first&.answers || Answer.none
    render Admin::QuestionsAndAnswersComponent.new(answers: answers)
  end

  # Questions with answers filled in
  def answered
    answers = Answer.where.not(answer: [ nil, "" ]).includes(:question).limit(5)
    render Admin::QuestionsAndAnswersComponent.new(answers: answers)
  end
end
