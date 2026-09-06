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
  # Length validations enforcing database column limits
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

  # +id+ last so the order is total: two members of one show can share a name
  # (and every unstamped row shares a NULL display_order), and MySQL is free to
  # return an undetermined tie either way from one query to the next.
  scope :ordered, -> {
    joins(:user)
      .order(Arel.sql("ISNULL(team_members.display_order), team_members.display_order ASC, " \
                      "users.first_name ASC, users.last_name ASC, team_members.id ASC"))
  }

  # The in-memory twin of +ordered+, for the edit form: after a failed save the
  # association holds the submitted rows with their errors, and a scope would
  # query the database and render the stale ones instead. A test pins the two
  # to the same order.
  #
  # Names are folded with +transliterate+ because the SQL side sorts them under
  # utf8mb4_unicode_ci, which ignores accents: a plain Ruby +downcase+ puts
  # "Ábel" after "Bob" and MySQL puts it before, so the form and the public page
  # would disagree — and the next save through the form would make the form's
  # order permanent. An unsaved row sorts after a saved one it ties with, being
  # the row that was just added.
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

  # The number an appended row should take, or nil when this teamwork is not
  # numbered at all.
  #
  # The obvious `display_order ||= max + 1` is a trap: on a teamwork whose rows
  # are all unstamped, +max+ is nil and the new row takes 0 -- and because NULLs
  # sort last (see +ordered+), that lifts it ABOVE every existing row instead of
  # appending to them. So a teamwork is either wholly numbered or wholly not,
  # which is the invariant TeamMemberOrdering maintains by stamping every row of
  # a submitted form at once.
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

  # Public because SchemaHelper reads crew credits with it; a second copy of this
  # regex elsewhere is a copy that drifts.
  def position_segments
    position.split(/\/(?![^(]*\))/).map(&:strip)
  end

  private

  # Rows written outside the admin form -- the bulk crew import, the "Proposer"
  # row on a new proposal, lib/tasks/imports.rake -- carried no display_order,
  # so a crew list imported in the producer's chosen order rendered alphabetised
  # until someone saved the form once. Numbering them here catches every writer,
  # rather than each having to remember.
  #
  # Skipped for an unsaved teamwork: imports.rake builds its rows against a Show
  # that has not been saved, so there are no siblings to count and querying for
  # them would look for teamwork_id NULL. Archive rows sort by name anyway,
  # which is exactly what an unnumbered teamwork gives.
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
