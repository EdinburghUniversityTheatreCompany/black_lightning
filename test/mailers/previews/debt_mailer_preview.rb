class DebtMailerPreview < ActionMailer::Preview
  def mail_debtor
    user = User.all.sample
    new_debtor = [ true, false ].sample

    DebtMailer.mail_debtor(user, new_debtor)
  end
end
