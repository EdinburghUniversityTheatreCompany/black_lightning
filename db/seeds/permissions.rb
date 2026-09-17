# Grid permissions the code gates on. Groups alone open nothing: without these a seeded Committee
# cannot enter the backend, the committee page or proposal review, because the granting data
# migrations were stamped as run by db:schema:load and never executed.
def seed_permission(group_name, action, subject_class)
  group = Group.find_by!(name: group_name)
  permission = find_or_seed(Admin::Permission, { action: action, subject_class: subject_class })
  group.permissions << permission unless group.permissions.include?(permission)
end

seed_permission("Member", "access", "backend")
seed_permission("Member", "sign_up_for", "Admin::StaffingJob")
seed_permission("Committee", "access", "backend")
seed_permission("Committee", "sign_up_for", "Admin::StaffingJob")
seed_permission("Committee", "access", "committee")
seed_permission("Committee", "review", "proposals")
