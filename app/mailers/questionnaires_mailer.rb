class QuestionnairesMailer < ApplicationMailer
  include NameHelper

  default reply_to: 'IT <it@bedlamtheatre.co.uk>'

  # Notifies all notify_emails on the questionnaire that there was an update.
  def notify(questionnaire, submitter, recipient_notify_email)
    @submitter = submitter

    @subject = "#{get_object_name(questionnaire, include_class_name: true)} updated by #{submitter.name}"
    @questionnaire_name = get_object_name(questionnaire, include_class_name: true, include_the: true)
    @questionnaire = questionnaire

    mail(to: recipient_notify_email.email, subject: @subject)
  end
end
