# Grid permissions the code gates on. Roles alone open nothing: without these a seeded Committee
# cannot enter the backend, the committee page or proposal review, because the granting data
# migrations were stamped as run by db:schema:load and never executed.
def seed_permission(role_name, action, subject_class)
  role = Role.find_by!(name: role_name)
  permission = find_or_seed(Admin::Permission, { action: action, subject_class: subject_class })
  role.permissions << permission unless role.permissions.include?(permission)
end

seed_permission("Member", "access", "backend")
seed_permission("Member", "sign_up_for", "Admin::StaffingJob")
seed_permission("Committee", "access", "backend")
seed_permission("Committee", "sign_up_for", "Admin::StaffingJob")
seed_permission("Committee", "access", "committee")
seed_permission("Committee", "review", "proposals")
