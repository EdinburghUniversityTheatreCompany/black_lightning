class QuestionnairesMailerPreview < ActionMailer::Preview
  def notify
    questionnaire = Admin::Questionnaires::Questionnaire.where.not(notify_emails: nil).sample || FactoryBot.create(:questionnaire)

    QuestionnairesMailer.notify(questionnaire)
  end
end
