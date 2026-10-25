# The "New Users to Create" section of an import preview: rows that matched nobody, each created
# on confirm unless skipped.
class Admin::ImportNewUsersComponent < ViewComponent::Base
  # hint: what confirming does with the new users.
  # create_label: the (preselected) radio that creates the user.
  # note_generated_email: marks the email the import made from the row's student id.
  # show_position: the position the row brings, in place of its id.
  def initialize(items:, hint:, create_label:, note_generated_email: true, show_position: false)
    @items = items
    @hint = hint
    @create_label = create_label
    @note_generated_email = note_generated_email
    @show_position = show_position
  end

  private

  def headers
    [ "Name", "Email", (@show_position ? "Position" : "ID"), [ "Action", "150px" ] ]
  end

  def generated_email?(row)
    @note_generated_email && row[:student_id].present? && row[:email] == "#{row[:student_id]}@ed.ac.uk"
  end
end
