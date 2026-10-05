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
  validates :position, length: { maximum: 255 }
  validates :teamwork_type, length: { maximum: 255 }
  validates :position, :user, presence: true
  validates_uniqueness_of :user_id, scope: [ :teamwork_type, :teamwork_id ]
  validate :uniqueness_in_parent_collection

  # It should not be optional, but otherwise this fails on creation when immediately attaching team members.
  # A little bit annoying, definitely.
  belongs_to :teamwork, polymorphic: true, optional: true
  belongs_to :user

  delegate :name, to: :user, prefix: true

  normalizes :position, with: ->(position) { position&.strip }

  before_validation :default_display_order, on: :create

  # id last so the order is total: names and NULL display_orders tie, and MySQL
  # may return a tie either way.
  scope :ordered, -> {
    joins(:user)
      .order(Arel.sql("ISNULL(team_members.display_order), team_members.display_order ASC, " \
                      "users.first_name ASC, users.last_name ASC, team_members.id ASC"))
  }

  # The in-memory twin of ordered, for the edit form: after a failed save a scope
  # would render the stale rows. transliterate because utf8mb4_unicode_ci folds
  # accents, and the form and the page must agree or the next save makes the
  # form's order permanent. An unsaved row sorts after a saved one it ties with.
  def self.in_display_order(members)
    members.to_a.sort_by do |member|
      [ member.display_order ? 0 : 1, member.display_order || 0,
        sort_name(member.user&.first_name), sort_name(member.user&.last_name),
        member.id || Float::INFINITY ]
    end
  end

  def self.sort_name(name)
    ActiveSupport::Inflector.transliterate(name.to_s).downcase
  end
  private_class_method :sort_name

  # nil for an unnumbered teamwork. Not max + 1 regardless: on an all-nil teamwork
  # that is 0, and as NULLs sort last the new row would jump ABOVE every existing
  # row. A teamwork is wholly numbered or wholly not.
  def self.next_display_order_for(teamwork)
    return 0 if teamwork.nil?
    return nil if teamwork.team_members.exists?(display_order: nil)

    (teamwork.team_members.maximum(:display_order) || -1) + 1
  end

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

  # Public because SchemaHelper reads it; a second copy of this regex would drift.
  def position_segments
    position.split(/\/(?![^(]*\))/).map(&:strip)
  end

  private

  # Numbers rows written outside the admin form (crew import, a proposal's
  # Proposer row). Skipped for an unsaved teamwork, which imports.rake builds:
  # there are no siblings to count, and archive rows sort by name anyway.
  def default_display_order
    return if display_order || teamwork.nil? || !teamwork.persisted?

    self.display_order = self.class.next_display_order_for(teamwork)
  end

  def sync_debts_if_show
    return unless teamwork.is_a?(Show)

    teamwork.sync_debts_for_user(user)
  end

  def uniqueness_in_parent_collection
    return unless teamwork && user_id
    return if teamwork.new_record?
    return if teamwork.respond_to?(:type_changed?) && teamwork.type_changed?

    # The loaded target, not a query, so the association cache is left intact.
    collection = teamwork.association(:team_members).target
    my_index = collection.index(self)

    duplicates = collection.each_with_index.select do |tm, idx|
      tm != self &&
      tm.user_id == user_id &&
      !tm.marked_for_destruction? &&
      (tm.persisted? || idx < my_index)
    end

    if duplicates.any?
      errors.add(:user_id, "is already a team member on this #{teamwork_type.underscore.humanize.downcase}")
    end
  end
end
