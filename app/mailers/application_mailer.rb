# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <website-noreply@notify.bedlamtheatre.co.uk>', reply_to: 'Committee <comittee@bedlamtheatre.co.uk>', parts_order: %w[text html]

  layout 'mailer'
end
