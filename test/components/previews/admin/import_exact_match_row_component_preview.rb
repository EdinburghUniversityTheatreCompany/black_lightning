class Admin::ImportExactMatchRowComponentPreview < Admin::ApplicationComponentPreview
  # A membership row matched by email, with the note the block adds under the user's name.
  def default
    item = { row: { original_name: "Finbar Viking", email: sample_user.email, student_id: "s1234567" }, existing_user: sample_user, index: 0 }
    render_with_template(locals: { item: item })
  end
end
