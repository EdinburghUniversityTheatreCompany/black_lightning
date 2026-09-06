class UsersTableComponentPreview < Admin::ApplicationComponentPreview
  # A plain list of users, with the search box above it.
  def default
    render UsersTableComponent.new(users: sample_users, url: "/admin/roles/1")
  end

  # A maintenance session, where the second column is attendance.
  def with_credit_counts
    users = sample_users
    render UsersTableComponent.new(users: users, url: "/admin/maintenance_sessions/1",
                                   credit_counts: users.to_h { |user| [ user.id, 2 ] })
  end

  # A role's membership list, where each row can be removed.
  def with_remove_buttons
    render UsersTableComponent.new(users: sample_users, url: "/admin/roles/1",
                                   show_remove_buttons: true,
                                   remove_url_helper: ->(id) { "/admin/roles/1/remove_user/#{id}" })
  end

  private

  def sample_users
    User.limit(5).to_a
  end
end
