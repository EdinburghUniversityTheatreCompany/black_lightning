class Admin::ImportNewUsersComponentPreview < Admin::ApplicationComponentPreview
  # The user import: an email made from the student id, and a row with neither.
  def default
    items = [
      { row: { original_name: "Finbar Viking", email: "s1234567@ed.ac.uk", student_id: "s1234567" }, index: 0 },
      { row: { original_name: "Ophelia Dane", email: nil }, index: 1 }
    ]
    render Admin::ImportNewUsersComponent.new(items: items, hint: "Will create new user accounts", create_label: "Create")
  end
end
