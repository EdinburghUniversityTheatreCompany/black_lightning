# == Schema Information
#
# Table name: climate_readings
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  dew_point_c          :decimal(5, 2)
#  raw_temperature      :decimal(7, 2)
#  raw_temperature_unit :string(1)
#  recorded_at          :datetime         not null
#  relative_humidity    :decimal(5, 2)
#  temperature_c        :decimal(5, 2)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  sensor_id            :bigint           not null
#
# Indexes
#
#  index_climate_readings_on_sensor_id_and_recorded_at  (sensor_id,recorded_at) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (sensor_id => climate_sensors.id) ON DELETE => cascade
#
module Climate
  ##
  # One sample from one sensor. Written only by Climate::ReadingIngest
  # (plausibility guard, dew point, upsert); nothing else should create these.
  class Reading < ApplicationRecord
    belongs_to :sensor, class_name: "Climate::Sensor", inverse_of: :readings

    validates :recorded_at, presence: true
    # Idempotency lives in the unique index: upsert_all skips validation and
    # collides there on purpose. This only makes create! fail readably.
    validates :recorded_at, uniqueness: { scope: :sensor_id }
    validates :raw_temperature_unit, length: { maximum: 1 }, allow_nil: true

    scope :between, ->(from, to) { where(recorded_at: from..to) }
    scope :chronological, -> { order(:recorded_at) }

    def dew_point_margin
      return nil if temperature_c.nil? || dew_point_c.nil?

      temperature_c - dew_point_c
    end
  end
end
