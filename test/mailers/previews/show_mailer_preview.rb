class ShowMailerPreview < ActionMailer::Preview
  def warn_committee_about_debtors_added_to_show
    show = Show.all.sample
    new_debtors_string = 'Finbar, Pineapple, and Hexagon'
    editor = User.all.sample

    ShowMailer.warn_committee_about_debtors_added_to_show(show, new_debtors_string, editor)
  end
end
