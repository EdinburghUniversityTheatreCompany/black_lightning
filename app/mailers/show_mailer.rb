class ShowMailer < ActionMailer::Base
  default from: 'Bedlam Theatre <no-reply@bedlamtheatre.co.uk>'

  def warn_committee_about_debtors_added_to_show(show, new_debtors_string, editor)
    @editor = editor
    @show = show
    @new_debtors_string = new_debtors_string

    mail(to: 'productions@bedlamtheatre.co.uk', subject: "New debtors added to #{@show.name}")
  end
end
