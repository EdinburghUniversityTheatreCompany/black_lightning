class AddCreateOpportunityPermissionToMemberRole < ActiveRecord::Migration[8.1]
  def up
    role = Role.find_by("LOWER(name) = ?", "member")

    # If the member role doesn't exist yet (e.g. fresh test DB), skip silently.
    return unless role

    permission = Admin::Permission.find_or_create_by!(action: "create", subject_class: "Opportunity")

    role.permissions << permission unless role.permissions.include?(permission)
  end

  def down
    permission = Admin::Permission.find_by(action: "create", subject_class: "Opportunity")
    return unless permission

    role = Role.find_by("LOWER(name) = ?", "member")
    return unless role

    role.permissions.delete(permission)
  end
end
