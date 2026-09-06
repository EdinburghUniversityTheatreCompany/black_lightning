# Ability used to grant proposal review to anyone holding a role NAMED "Proposal Checker" or
# "Committee". It now reads the `review Admin::Proposals::Proposal` grid permission, so both roles
# must hold it or the deploy takes their post-deadline view of proposals away.
#
# Data-only. Test and CI databases are schema-loaded, so this never runs there — the fixtures
# grant the same permission.
class GrantProposalReviewPermission < ActiveRecord::Migration[8.1]
  ROLE_NAMES = %w[committee proposal\ checker].freeze

  def up
    permission = Admin::Permission.find_or_create_by!(action: "review", subject_class: "Admin::Proposals::Proposal")

    roles.each do |role|
      role.permissions << permission unless role.permissions.include?(permission)
      say "Granted proposal review to role '#{role.name}'"
    end
    (ROLE_NAMES - roles.map { |role| role.name.downcase }).each do |missing|
      say "No role named '#{missing}' found: it was NOT granted proposal review. Grant it in the grid."
    end
  end

  def down
    permission = Admin::Permission.find_by(action: "review", subject_class: "Admin::Proposals::Proposal")
    return unless permission

    roles.each { |role| role.permissions.delete(permission) }
  end

  private

  def roles
    Role.where("LOWER(name) IN (?)", ROLE_NAMES)
  end
end
