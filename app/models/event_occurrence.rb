##
# One dated instance of an Event: a performance of a show, a session of a
# workshop, an opening time of a season.
#
# One table for all three because the columns are identical; what differs is
# only what to call them, which each Event subclass answers with
# +OCCURRENCE_LABEL+. See Event#occurrence_label.
#
# An event with NO occurrences is not an event that never happens -- it is the
# ~3000 archive rows and anything a producer has not filled in yet, and it means
# "every day of the run". That fallback lives in Event#on_today?.
##
# == Schema Information
#
# Table name: event_occurrences
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  access_flags       :json
#  admission_at       :datetime
#  cancelled          :boolean
#  ends_at            :datetime
#  note               :string(255)
#  sold_out           :boolean
#  starts_at          :datetime         not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  event_id           :integer          not null
#  pretix_subevent_id :bigint
#
# Indexes
#
#  index_event_occurrences_on_event_id_and_starts_at  (event_id,starts_at)
#  index_event_occurrences_on_pretix_subevent_id      (pretix_subevent_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (event_id => events.id)
#
class EventOccurrence < ApplicationRecord
  # A constant rather than seven boolean columns, so adding a flag is one line
  # instead of a migration. Order is the order they render in.
  #
  # Written labels first, with the stored values derived from them, so a new flag
  # cannot be added to one and forgotten in the other. They are not humanize-able:
  # that renders "bsl" as "Bsl".
  ACCESS_FLAG_LABELS = {
    "preview" => "Preview",
    "press_night" => "Press night",
    "relaxed" => "Relaxed",
    "captioned" => "Captioned",
    "audio_described" => "Audio described",
    "bsl" => "BSL interpreted",
    "post_show_discussion" => "Post-show discussion"
  }.freeze

  ACCESS_FLAGS = ACCESS_FLAG_LABELS.keys.freeze

  # schema.org accessibilityFeature values for the flags that ARE accessibility
  # features. Preview, press night and post-show discussion are scheduling
  # labels, not access provision, and publishing them here would tell a search
  # engine a press night is an accessible performance.
  SCHEMA_ACCESSIBILITY_FEATURES = {
    "captioned" => "captions",
    "audio_described" => "audioDescription",
    "bsl" => "signLanguage",
    "relaxed" => "relaxedPerformance"
  }.freeze

  belongs_to :event

  validates :starts_at, presence: true
  validates :note, length: { maximum: 255 }
  validate :ends_at_after_starts_at
  validate :starts_at_within_run
  validate :access_flags_are_known

  has_paper_trail

  normalizes :note, with: ->(value) { value&.strip }
  normalizes :access_flags, with: ->(value) {
    Array(value).map { |flag| flag.to_s.strip }.reject(&:blank?).uniq
  }

  default_scope -> { order(:starts_at) }

  # The column is nullable -- MySQL will not take a literal default on a JSON
  # column -- so a row that never had flags reads back nil, and every caller
  # would need to know that.
  def access_flags
    super || []
  end

  def access_flag?(flag)
    access_flags.include?(flag.to_s)
  end

  # Nullable columns, like access_flags above: every row predating the pretix
  # sync reads back nil, and no view should have to know that.
  def sold_out? = super || false

  def cancelled? = super || false

  # The written labels for what this occurrence is flagged as, in the constant's
  # order rather than the order they happen to be stored in.
  def access_flag_labels
    ACCESS_FLAG_LABELS.filter_map { |flag, label| label if access_flags.include?(flag) }
  end

  def on_date
    starts_at&.to_date
  end

  # Only the flags that are genuinely about access, in schema.org's vocabulary.
  def schema_accessibility_features
    access_flags.filter_map { |flag| SCHEMA_ACCESSIBILITY_FEATURES[flag] }
  end

  # When this one finishes. An explicit ends_at wins; otherwise the event's
  # running time supplies it, which is the usual case -- a producer states the
  # running time once rather than an end time per night.
  def effective_ends_at
    return ends_at if ends_at.present?
    return nil if starts_at.blank? || event&.duration_minutes.blank?

    starts_at + event.duration_minutes.minutes
  end

  # pretix states an admission time per date; we state one offset for the whole
  # run. The specific one wins, so a synced press night with earlier doors is not
  # overwritten by the event-wide answer.
  def doors_open_at
    return admission_at if admission_at.present?
    return nil if starts_at.blank? || event&.doors_open_minutes_before.blank?

    starts_at - event.doors_open_minutes_before.minutes
  end

  # Whether Pretix::PerformanceSync owns this row. A row with no subevent id was
  # typed by hand -- a preview, a get-in, a schools matinee not sold through the
  # shop -- and the sync never reads, updates or deletes it.
  def pretix_synced?
    pretix_subevent_id.present?
  end

  private

  def ends_at_after_starts_at
    return if ends_at.blank? || starts_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, "must be after the start time")
  end

  ##
  # The run dates and the occurrence list state the same fact twice. Without
  # this they can contradict each other, and nothing downstream -- the display's
  # next_occurrence, the sitemap, the schema.org output -- has any way to tell
  # which one is lying.
  ##
  def starts_at_within_run
    return if starts_at.blank? || event.nil?
    return if event.start_date.blank? || event.end_date.blank?
    return if (event.start_date..event.end_date).cover?(starts_at.to_date)

    errors.add(:starts_at, "must fall between the event's start and end dates")
  end

  def access_flags_are_known
    unknown = access_flags - ACCESS_FLAGS

    return if unknown.empty?

    errors.add(:access_flags, "includes unknown #{'flag'.pluralize(unknown.size)}: #{unknown.to_sentence}")
  end
end
