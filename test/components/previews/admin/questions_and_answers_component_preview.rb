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

  # An answer carrying more than one attachment renders the multi-attachment
  # gallery (admin/shared/attachments_gallery) rather than a single show_attachment.
  # This is the branch that 500'd in production (error 132814643) when the partial
  # path was wrong.
  def multiple_attachments
    answer_ids = Attachment.where(item_type: "Admin::Answer")
                           .group(:item_id)
                           .having("COUNT(*) > 1")
                           .pluck(:item_id)
    answers = Answer.where(id: answer_ids).includes(:question).limit(5)
    render Admin::QuestionsAndAnswersComponent.new(answers: answers)
  end
end
