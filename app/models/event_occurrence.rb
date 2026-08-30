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
#  id           :bigint           not null, primary key
#  access_flags :json
#  ends_at      :datetime
#  note         :string(255)
#  starts_at    :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  event_id     :integer          not null
#
# Indexes
#
#  index_event_occurrences_on_event_id_and_starts_at  (event_id,starts_at)
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

  # The written labels for what this occurrence is flagged as, in the constant's
  # order rather than the order they happen to be stored in.
  def access_flag_labels
    ACCESS_FLAG_LABELS.filter_map { |flag, label| label if access_flags.include?(flag) }
  end

  def on_date
    starts_at&.to_date
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
