# == Schema Information
#
# Table name: groups
# Database name: primary
#
#  id            :integer          not null, primary key
#  name          :string(255)
#  resource_type :string(255)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  resource_id   :bigint
#
# Indexes
#
#  index_user_groups_on_name                                    (name)
#  index_user_groups_on_name_and_resource_type_and_resource_id  (name,resource_type,resource_id)
#  index_user_groups_on_resource_type_and_resource_id           (resource_type,resource_id)
#
class Group < ApplicationRecord
  # Length validations enforcing database column limits
  validates :name, length: { maximum: 255 }
  validates :resource_type, length: { maximum: 255 }
  # The groups that are referenced directly in the code (`in_group?` / `in_group`).
  # Renaming one would silently break every such check, so these names cannot be changed.
  # Matched case-insensitively (`hardcoded_name?`): the code asks for :member and "Member" alike,
  # which MySQL's collation happily equates, so the guard must not be the one place casing matters.
  # Archiving is unaffected — it creates a suffixed sibling group and never renames this one.
  HARDCODED_NAMES = [ "Admin", "Committee", "Member", "Life Member", "DM Trained", "Business Manager", "First Aid Trained", "Bar Trained", "Tool Trained", "Opportunity Reviewer", "Advance Proposal Checker" ].freeze
  NON_PURGEABLE_NAMES = [ "member", "life member" ]

  validates :name, presence: true
  validate :name_not_hardcoded

  before_destroy :prevent_hardcoded_or_non_purgeable_destruction

  has_and_belongs_to_many :parents, class_name: "Group", join_table: :groups_parents, foreign_key: :group_id, association_foreign_key: :parent_id
  has_and_belongs_to_many :children, class_name: "Group", join_table: :groups_parents, foreign_key: :parent_id, association_foreign_key: :group_id
  has_and_belongs_to_many :users
  has_and_belongs_to_many :permissions, class_name: "Admin::Permission"

  belongs_to :resource, polymorphic: true, optional: true

  accepts_nested_attributes_for :children, :parents, reject_if: :all_blank, allow_destroy: true

  scope :trained, -> { where("name LIKE ?", "%Trained%") }

  normalizes :name, with: ->(name) { name&.strip }

  def self.ransackable_attributes(auth_object = nil)
    %w[name]
  end

  def self.hardcoded_name?(name)
    HARDCODED_NAMES.any? { |hardcoded| hardcoded.casecmp?(name.to_s.strip) }
  end

  def self.resolve(group)
    if group.is_a? String
      group = Group.where("LOWER(name) LIKE ?", "#{group.downcase}").first
    elsif group.is_a? Symbol
      group = Group.where("LOWER(name) LIKE ?", "#{group.downcase}").first
    elsif not (group.is_a? Group)
      # who am i to complain?
    end

    group
  end

  # Removes all users from the group.
  def purge
    # You cannot purge certain group.
    return false if NON_PURGEABLE_NAMES.include?(name.downcase.strip)

    ActiveRecord::Base.transaction do
      self.users.clear
    end
  end
  # Moves all users on this group to a new group with the academic year shorthand as a suffix.
  # This new group has no permissions, and the existing group keeps all permissions.
  def archive(suffix)
    if suffix.blank?
      errors.add(:base, "Suffix cannot be blank when archiving a group")
      return false
    end

    # Captured BEFORE the clear, and synced only after the transaction commits.
    # `users.clear` is delete_all, which fires no association callbacks at all,
    # so nothing downstream can observe this the way it observes join_group — and
    # archiving `member` is precisely the moment the whole society stops being
    # members. Enqueuing inside the transaction would tell pretix about a
    # revocation that a rollback then undid.
    archived_user_ids = users.ids

    ActiveRecord::Base.transaction do
      # Create or find the archival group and move all users over.
      group = Group.find_or_create_by(name: "#{name} #{suffix}")
      group.users << self.users

      # Then clear them from this group.
      self.users.clear
    end

    sync_pretix_memberships(archived_user_ids)
    true
  end

  def children_attributes=(attributes)
    cycle_through_attributes(attributes, children)
  end

  def parents_attributes=(attributes)
    cycle_through_attributes(attributes, parents)
  end

  def name_not_hardcoded
    errors.add(:name, "is hardcoded and cannot be altered") if Group.hardcoded_name?(name_was) && !name.to_s.casecmp?(name_was.to_s)
  end

  def trained_group?
    name&.include?("Trained")
  end

  def remove_user(user)
    user.leave_group self
  end

  private

  # Only the two roles that actually entitle someone to member pricing are worth
  # a pretix round trip; archiving "DM Trained" would otherwise enqueue a job per
  # holder to discover each is a no-op.
  def sync_pretix_memberships(user_ids)
    return unless Pretix::MembershipSync::ENTITLING_ROLES.include?(name.to_s.downcase.strip)

    Pretix::SyncMembershipJob.enqueue_for(user_ids)
  end

  def prevent_hardcoded_or_non_purgeable_destruction
    if NON_PURGEABLE_NAMES.include?(name&.downcase&.strip)
      errors.add(:base, "Cannot delete group '#{name}' as it is protected from deletion")
      throw(:abort)
    elsif Group.hardcoded_name?(name)
      errors.add(:base, "Cannot delete hardcoded group '#{name}' as it is referenced in code")
      throw(:abort)
    end
  end

  def cycle_through_attributes(attributes, collection)
    attributes.each do |attribute|
      id = attribute[1][:id]
      next if id == ""

      group = Group.find(id)

      collection << group unless collection.all.include?(group)

      collection.delete(group) if attribute[1][:_destroy] == "1"
    end
  end
end
