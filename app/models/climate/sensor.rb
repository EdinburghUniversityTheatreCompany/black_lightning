# == Schema Information
#
# Table name: climate_sensors
# Database name: primary
#
#  id             :bigint           not null, primary key
#  active         :boolean          default(FALSE), not null
#  display_name   :string(255)      not null
#  in_crypt       :boolean          default(FALSE), not null
#  last_error     :string(500)
#  last_polled_at :datetime
#  latitude       :decimal(9, 6)
#  location       :string(255)
#  longitude      :decimal(9, 6)
#  placement      :string(255)      default("indoor"), not null
#  position       :integer          default(0), not null
#  source         :string(255)      default("govee"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_climate_sensors_on_active  (active)
#
module Climate
  ##
  # A source of temperature/humidity readings. The crypt's Govee sensors and the
  # outdoor weather feed are both rows here, differing only in how readings
  # arrive: a Govee sensor is fed by CSV import, the outdoor row by an hourly
  # poll. See the migration for why they share a table.
  class Sensor < ApplicationRecord
    SOURCE_GOVEE = "govee".freeze
    SOURCE_OPEN_METEO = "open_meteo".freeze
    SOURCES = [ SOURCE_GOVEE, SOURCE_OPEN_METEO ].freeze

    PLACEMENT_INDOOR = "indoor".freeze
    PLACEMENT_OUTDOOR = "outdoor".freeze
    PLACEMENTS = [ PLACEMENT_INDOOR, PLACEMENT_OUTDOOR ].freeze

    # A Govee sensor is only as fresh as the last CSV somebody imported, so its
    # window is a day rather than minutes. The outdoor feed polls hourly.
    STALE_AFTER = { SOURCE_GOVEE => 26.hours, SOURCE_OPEN_METEO => 3.hours }.freeze
    DEFAULT_STALE_AFTER = 26.hours

    has_many :readings, class_name: "Climate::Reading", dependent: :delete_all, inverse_of: :sensor

    validates :display_name, presence: true, length: { maximum: 255 }
    validates :location, length: { maximum: 255 }, allow_nil: true
    validates :source, inclusion: { in: SOURCES }, length: { maximum: 255 }
    validates :placement, inclusion: { in: PLACEMENTS }, length: { maximum: 255 }
    validates :last_error, length: { maximum: 500 }, allow_nil: true
    validates :latitude, :longitude, presence: true, if: :open_meteo?
    validates :latitude, numericality: { in: -90..90 }, allow_nil: true
    validates :longitude, numericality: { in: -180..180 }, allow_nil: true
    validate :outdoor_feed_is_not_in_the_crypt

    scope :active, -> { where(active: true) }
    scope :govee, -> { where(source: SOURCE_GOVEE) }
    scope :open_meteo, -> { where(source: SOURCE_OPEN_METEO) }
    scope :outdoor, -> { where(placement: PLACEMENT_OUTDOOR) }
    # Indoor sensors first, then the outdoor comparison line.
    scope :in_display_order, -> { order(Arel.sql("placement = 'outdoor'"), :position, :id) }
    # Which sensors the condensation-risk and ventilation charts read.
    scope :in_crypt, -> { where(in_crypt: true) }

    # Ensured here rather than seeded by a data migration: test and CI databases
    # are schema-LOADED, so a data migration would leave every environment
    # except production without the row. The outdoor poll job calls this first.
    #
    # find_or_create_by only assigns on create, so a corrected location survives.
    def self.outdoor_source!
      find_or_create_by!(source: SOURCE_OPEN_METEO) do |sensor|
        sensor.placement = PLACEMENT_OUTDOOR
        sensor.display_name = "Outside (Open-Meteo)"
        sensor.location = "Bedlam Theatre, Edinburgh"
        # Open-Meteo snaps to a ~1 km grid, so these only have to pick the cell.
        sensor.latitude = 55.9467
        sensor.longitude = -3.1903
        sensor.active = true
        sensor.position = 100 # sorts after the indoor sensors
      end
    end

    def govee? = source == SOURCE_GOVEE
    def open_meteo? = source == SOURCE_OPEN_METEO
    def outdoor? = placement == PLACEMENT_OUTDOOR

    def latest_reading
      return @latest_reading if defined?(@latest_reading)

      @latest_reading = readings.order(recorded_at: :desc).first
    end

    def stale_after = STALE_AFTER.fetch(source, DEFAULT_STALE_AFTER)

    # No readings at all counts as stale, which is the same story for the operator.
    def stale?(now = Time.current)
      latest_reading.nil? || latest_reading.recorded_at < now - stale_after
    end

    def to_label = display_name

    private

    # The Open-Meteo row models the air outside the building. Letting it be
    # ticked would put the outdoor line into the crypt's own worst case.
    def outdoor_feed_is_not_in_the_crypt
      errors.add(:in_crypt, "cannot be set on the outdoor feed") if in_crypt? && outdoor?
    end
  end
end
