##
# Represents a collection of Users that have specific positions.
#
# Used by Event, Admin::Proposals::Proposal
#
# == Schema Information
#
# Table name: team_members
# Database name: primary
#
#  id            :integer          not null, primary key
#  display_order :integer
#  position      :string(255)
#  teamwork_type :string(255)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  teamwork_id   :integer
#  user_id       :integer
#
# Indexes
#
#  index_team_members_on_display_order         (display_order)
#  index_team_members_on_teamwork_and_user     (teamwork_id,teamwork_type,user_id) UNIQUE
#  index_team_members_on_teamwork_id           (teamwork_id)
#  index_team_members_on_teamwork_type         (teamwork_type)
#  index_team_members_on_teamwork_type_and_id  (teamwork_type,teamwork_id)
#  index_team_members_on_user_id               (user_id)
#
class TeamMember < ActiveRecord::Base
  validates :position, :user, presence: true
  validates_uniqueness_of :user_id, scope: [ :teamwork_type, :teamwork_id ]
  validate :uniqueness_in_parent_collection

  # It should not be optional, but otherwise this fails on creation when immediately attaching team members.
  # A little bit annoying, definitely.
  belongs_to :teamwork, polymorphic: true, optional: true
  belongs_to :user

  delegate :name, to: :user, prefix: true

  normalizes :position, with: ->(position) { position&.strip }

  scope :ordered, -> {
    joins(:user)
      .order(Arel.sql("ISNULL(team_members.display_order), team_members.display_order ASC, users.first_name ASC, users.last_name ASC"))
  }

  after_create :sync_debts_if_show

  ACTOR_PATTERN = /\A(actor|cast)\s*\((.+)\)\s*\z/i

  def cast?
    position_segments.any? { |s| s.match?(ACTOR_PATTERN) }
  end

  def cast_display_name
    acting = position_segments
      .filter_map { |s| s.match(ACTOR_PATTERN)&.[](2)&.strip }
      .join(", ")
    crew = position_segments.reject { |s| s.match?(ACTOR_PATTERN) }.map(&:strip)
    crew.any? ? Rails::Html::SafeListSanitizer.new.sanitize("#{acting} / Crew<wbr>(#{crew.join(", ")})", tags: [ "wbr" ]).html_safe : acting
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[position user_id teamwork_id teamwork_type]
  end

  private

  def position_segments
    position.split(/\/(?![^(]*\))/).map(&:strip)
  end

  def sync_debts_if_show
    return unless teamwork.is_a?(Show)

    teamwork.sync_debts_for_user(user)
  end

  def uniqueness_in_parent_collection
    return unless teamwork && user_id
    return if teamwork.new_record?
    return if teamwork.respond_to?(:type_changed?) && teamwork.type_changed?

    # Access the association's internal target without loading from database
    # This should avoid corrupting the association cache
    collection = teamwork.association(:team_members).target
    my_index = collection.index(self)

    duplicates = collection.each_with_index.select do |tm, idx|
      tm != self && # Not the same object
      tm.user_id == user_id && # Same user
      !tm.marked_for_destruction? && # Not being deleted
      (tm.persisted? || idx < my_index) # Either saved OR appears earlier in collection
    end

    if duplicates.any?
      errors.add(:user_id, "is already a team member on this #{teamwork_type.underscore.humanize.downcase}")
    end
  end
end
