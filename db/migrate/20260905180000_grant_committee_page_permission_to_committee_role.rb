# The committee resources page used to check `has_role?("Committee")` in the controller. It now
# checks the `access committee` grid permission, so the Committee role must hold that permission
# or the deploy locks committee out of their own page.
#
# Data-only. Test and CI databases are schema-loaded, so this never runs there — the fixtures
# grant the same permission.
class GrantCommitteePagePermissionToCommitteeRole < ActiveRecord::Migration[8.1]
  def up
    role = Role.find_by("LOWER(name) = ?", "committee")
    unless role
      say "No role named 'committee' found: NOBODY was granted the committee page. Grant it in the grid."
      return
    end

    permission = Admin::Permission.find_or_create_by!(action: "access", subject_class: "committee")
    role.permissions << permission unless role.permissions.include?(permission)
    say "Granted 'access committee' to role '#{role.name}'"
  end

  def down
    permission = Admin::Permission.find_by(action: "access", subject_class: "committee")
    return unless permission

    Role.find_by("LOWER(name) = ?", "committee")&.permissions&.delete(permission)
  end
end
