class Admin::ImportPossibleMatchesComponentPreview < Admin::ApplicationComponentPreview
  # The user import's wording: link to a candidate, or a different person.
  def default
    render Admin::ImportPossibleMatchesComponent.new(items: [ item ], years_active: { sample_user.id => [ 2023, 2024 ] })
  end

  # The membership import merges into a candidate instead.
  def membership
    render Admin::ImportPossibleMatchesComponent.new(items: [ item ], years_active: {}, choice: "merge",
                                                     choice_label_prefix: "Merge with ", create_label: "Create New")
  end

  # The crew import shows each row's position and no ids.
  def crew
    render Admin::ImportPossibleMatchesComponent.new(items: [ item ], years_active: {}, show_ids: false, show_position: true)
  end

  private

  def item
    { row: { original_name: "Finbar Viking", email: "finbar@example.com", student_id: "s1234567", position: "Director" },
      existing_users: [ sample_user ], index: 0 }
  end
end
