class ShowMailer < ApplicationMailer
  def warn_committee_about_debtors_added_to_show(show, new_debtors_string, editor)
    @editor = editor
    @show = show
    @new_debtors_string = new_debtors_string

    @subject = "New debtors added to #{@show.name}"

    mail(to: 'productions@bedlamtheatre.co.uk', subject: @subject)
  end
end
