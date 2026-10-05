##
# One dated instance of an Event: a performance, a workshop session or a season's
# opening time. An event with none plays every day of its run (Event#on_today?).
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
  # In render order. Written out because "bsl".humanize is "Bsl".
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

  # The two state lines the event page renders beside the access flags. Named
  # here rather than typed into the view, which has to style them differently:
  # "Relaxed" is information, "Cancelled" is a wasted journey.
  CANCELLED_LABEL = "Cancelled".freeze
  SOLD_OUT_LABEL = "Sold out".freeze

  # Only the flags that are access provision. Preview, press night and post-show
  # discussion are scheduling labels: publishing them would call a press night
  # accessible.
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

  # MySQL takes no literal default on a JSON column, so an unset row reads nil.
  def access_flags
    super || []
  end

  def access_flag?(flag)
    access_flags.include?(flag.to_s)
  end

  # Nullable: rows predating the pretix sync read nil.
  def sold_out? = super || false

  def cancelled? = super || false

  # In the constant's order, not the stored one.
  def access_flag_labels
    ACCESS_FLAG_LABELS.filter_map { |flag, label| label if access_flags.include?(flag) }
  end

  def on_date
    starts_at&.to_date
  end

  def schema_accessibility_features
    access_flags.filter_map { |flag| SCHEMA_ACCESSIBILITY_FEATURES[flag] }
  end

  # An explicit ends_at wins; otherwise the event's running time supplies it.
  def effective_ends_at
    return ends_at if ends_at.present?
    return nil if starts_at.blank? || event&.duration_minutes.blank?

    starts_at + event.duration_minutes.minutes
  end

  # pretix's per-date admission time wins over the event-wide offset, so a synced
  # press night keeps its earlier doors.
  def doors_open_at
    return admission_at if admission_at.present?
    return nil if starts_at.blank? || event&.doors_open_minutes_before.blank?

    starts_at - event.doors_open_minutes_before.minutes
  end

  # A row with no subevent id was typed by hand, and the sync never touches it.
  def pretix_synced?
    pretix_subevent_id.present?
  end

  private

  def ends_at_after_starts_at
    return if ends_at.blank? || starts_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, "must be after the start time")
  end

  # The run dates and the occurrences state the same fact; without this they can
  # contradict each other with nothing downstream able to tell which is wrong.
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
