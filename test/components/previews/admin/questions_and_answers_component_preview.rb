class Admin::QuestionsAndAnswersComponentPreview < Admin::ApplicationComponentPreview
  def unanswered
    answers = Admin::Questionnaires::Questionnaire.joins(:answers).first&.answers || Admin::Answer.none
    render Admin::QuestionsAndAnswersComponent.new(answers: answers)
  end

  def answered
    render Admin::QuestionsAndAnswersComponent.new(answers: Admin::Answer.where.not(answer: [ nil, "" ]).limit(5))
  end

  def multiple_attachments
    answer_ids = Attachment.where(item_type: "Admin::Answer").reorder(nil).group(:item_id).having("COUNT(*) > 1").select(:item_id)
    render Admin::QuestionsAndAnswersComponent.new(answers: Admin::Answer.where(id: answer_ids).limit(5))
  end
end
