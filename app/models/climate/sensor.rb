# == Schema Information
#
# Table name: climate_sensors
# Database name: primary
#
#  id               :bigint           not null, primary key
#  active           :boolean          default(FALSE), not null
#  display_name     :string(255)      not null
#  last_error       :string(500)
#  last_polled_at   :datetime
#  latitude         :decimal(9, 6)
#  location         :string(255)
#  longitude        :decimal(9, 6)
#  placement        :string(255)      default("indoor"), not null
#  position         :integer          default(0), not null
#  sku              :string(255)
#  source           :string(255)      default("govee"), not null
#  temperature_unit :string(255)
#  unit_verified_at :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  external_id      :string(255)
#
# Indexes
#
#  index_climate_sensors_on_active                  (active)
#  index_climate_sensors_on_source_and_external_id  (source,external_id) UNIQUE
#
module Climate
  ##
  # A source of temperature/humidity readings. Both the Govee thermo-hygrometers
  # in the crypt and the outdoor weather feed are rows here — see the migration
  # for why they share a table.
  class Sensor < ApplicationRecord
    SOURCE_GOVEE = "govee".freeze
    SOURCE_OPEN_METEO = "open_meteo".freeze
    SOURCES = [ SOURCE_GOVEE, SOURCE_OPEN_METEO ].freeze

    PLACEMENT_INDOOR = "indoor".freeze
    PLACEMENT_OUTDOOR = "outdoor".freeze
    PLACEMENTS = [ PLACEMENT_INDOOR, PLACEMENT_OUTDOOR ].freeze

    UNIT_CELSIUS = "celsius".freeze
    UNIT_FAHRENHEIT = "fahrenheit".freeze
    UNITS = [ UNIT_CELSIUS, UNIT_FAHRENHEIT ].freeze

    # How long a sensor may go unheard-from before the dashboard flags it. Both
    # are roughly three missed polls: long enough that one failed cycle isn't
    # alarming, short enough that a dead sensor is obvious within the hour.
    STALE_AFTER = { SOURCE_GOVEE => 35.minutes, SOURCE_OPEN_METEO => 3.hours }.freeze
    DEFAULT_STALE_AFTER = 1.hour

    has_many :readings, class_name: "Climate::Reading", dependent: :delete_all, inverse_of: :sensor

    validates :display_name, presence: true, length: { maximum: 255 }
    validates :location, length: { maximum: 255 }, allow_nil: true
    validates :source, inclusion: { in: SOURCES }, length: { maximum: 255 }
    validates :placement, inclusion: { in: PLACEMENTS }, length: { maximum: 255 }
    validates :temperature_unit, inclusion: { in: UNITS }, length: { maximum: 255 }, allow_nil: true
    validates :external_id, presence: true, if: :govee?
    validates :external_id, length: { maximum: 255 }, allow_nil: true
    # Discover upserts on this pair, so it must not register a device twice. The
    # database index is the real guarantee; this gives the create! path a
    # readable error instead of RecordNotUnique.
    validates :external_id, uniqueness: { scope: :source }, allow_nil: true
    validates :sku, length: { maximum: 255 }, allow_nil: true
    # Truncated to fit by the poll jobs; validated so a hand-set value can't
    # silently overflow the column.
    validates :last_error, length: { maximum: 500 }, allow_nil: true
    validates :latitude, :longitude, presence: true, if: :open_meteo?
    validates :latitude, numericality: { in: -90..90 }, allow_nil: true
    validates :longitude, numericality: { in: -180..180 }, allow_nil: true

    scope :active, -> { where(active: true) }
    scope :govee, -> { where(source: SOURCE_GOVEE) }
    scope :open_meteo, -> { where(source: SOURCE_OPEN_METEO) }
    scope :outdoor, -> { where(placement: PLACEMENT_OUTDOOR) }
    # Indoor first, then the outdoor comparison line — the reading order of the
    # chart legend and the tile row.
    scope :in_display_order, -> { order(Arel.sql("placement = 'outdoor'"), :position, :id) }

    # The outdoor comparison line. There is exactly one, it needs no discovery
    # step, and it is ensured here rather than seeded by a data migration:
    # test and CI databases are schema-LOADED, not migrated, so a data migration
    # would leave every environment except production without the row. The
    # outdoor poll job calls this before every run.
    #
    # find_or_create_by only assigns on create, so an operator who corrects the
    # coordinates keeps their correction.
    def self.outdoor_source!
      find_or_create_by!(source: SOURCE_OPEN_METEO, external_id: nil) do |sensor|
        sensor.placement = PLACEMENT_OUTDOOR
        sensor.display_name = "Outside (Open-Meteo)"
        sensor.location = "Bedlam Theatre, Edinburgh"
        # Bedlam Theatre, 11b Bristo Place, EH1 1EZ. Open-Meteo snaps to its own
        # ~1 km grid, so these only have to pick the right cell.
        sensor.latitude = 55.9467
        sensor.longitude = -3.1903
        # Nothing to verify — Open-Meteo documents and returns Celsius.
        sensor.temperature_unit = UNIT_CELSIUS
        sensor.unit_verified_at = Time.current
        sensor.active = true
        sensor.position = 100 # sorts after the indoor sensors
      end
    end

    def govee? = source == SOURCE_GOVEE
    def open_meteo? = source == SOURCE_OPEN_METEO
    def outdoor? = placement == PLACEMENT_OUTDOOR

    # The gate on the whole ingest path. A sensor whose unit nobody has confirmed
    # writes nothing at all — see Climate::ReadingIngest.
    def unit_verified? = temperature_unit.present?

    def fahrenheit? = temperature_unit == UNIT_FAHRENHEIT

    def latest_reading
      return @latest_reading if defined?(@latest_reading)

      @latest_reading = readings.order(recorded_at: :desc).first
    end

    def stale_after = STALE_AFTER.fetch(source, DEFAULT_STALE_AFTER)

    # A sensor with no readings at all counts as stale: on the dashboard that is
    # the same "you are not getting data from this" story, and it needs saying.
    def stale?(now = Time.current)
      latest_reading.nil? || latest_reading.recorded_at < now - stale_after
    end

    def to_label = display_name
  end
end
