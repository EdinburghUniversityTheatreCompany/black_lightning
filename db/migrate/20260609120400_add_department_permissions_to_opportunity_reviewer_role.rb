class AddDepartmentPermissionsToOpportunityReviewerRole < ActiveRecord::Migration[8.1]
  ACTIONS = %w[read create update delete].freeze

  def up
    role = Role.find_by(name: "Opportunity Reviewer")
    return unless role

    ACTIONS.each do |action|
      permission = Admin::Permission.find_or_create_by!(action: action, subject_class: "Department")
      role.permissions << permission unless role.permissions.include?(permission)
    end
  end

  def down
    role = Role.find_by(name: "Opportunity Reviewer")
    return unless role

    ACTIONS.each do |action|
      permission = Admin::Permission.find_by(action: action, subject_class: "Department")
      role.permissions.delete(permission) if permission
    end
  end
end
