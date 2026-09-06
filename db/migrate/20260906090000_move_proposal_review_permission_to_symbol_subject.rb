# 20260905181000 stored the review permission under subject_class "Admin::Proposals::Proposal".
# That class is excluded from the grid's model rows, so listing it as a miscellaneous subject
# made every grid save call update_permission for it with only "review" — deleting the
# read/update/manage rows that predate the exclusion (2026-05-08), which is how a non-admin
# approves proposals. The permission now lives under the symbol subject "proposals", matching
# `backend` / `committee` / `reports`. Role links follow the row.
#
# Data-only and idempotent. Test and CI databases are schema-loaded, so this never runs there —
# the fixtures carry the symbol subject.
class MoveProposalReviewPermissionToSymbolSubject < ActiveRecord::Migration[8.1]
  OLD = { action: "review", subject_class: "Admin::Proposals::Proposal" }.freeze
  NEW = { action: "review", subject_class: "proposals" }.freeze
  ROLE_NAMES = %w[committee proposal\ checker].freeze

  def up
    move(OLD, NEW)
    grant_to_default_roles
  end

  def down
    move(NEW, OLD)
  end

  private

  # Rename `from` to `to`, merging role links if both rows already exist.
  def move(from, to)
    source = Admin::Permission.find_by(from)
    return unless source

    target = Admin::Permission.find_by(to)
    if target
      source.roles.each { |role| target.roles << role unless target.roles.include?(role) }
      source.roles.clear
      source.destroy!
    else
      source.update!(to)
    end
    say "Moved '#{from[:action]} #{from[:subject_class]}' to '#{to[:action]} #{to[:subject_class]}'"
  end

  # Re-asserted here rather than trusting 20260905181000 ran against the same rows.
  def grant_to_default_roles
    permission = Admin::Permission.find_or_create_by!(NEW)
    roles = Role.where("LOWER(name) IN (?)", ROLE_NAMES)

    roles.each do |role|
      role.permissions << permission unless role.permissions.include?(permission)
      say "Role '#{role.name}' holds proposal review"
    end
    (ROLE_NAMES - roles.map { |role| role.name.downcase }).each do |missing|
      say "No role named '#{missing}' found: it does NOT hold proposal review. Grant it in the grid."
    end
  end
end
