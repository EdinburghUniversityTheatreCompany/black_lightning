# The outdoor comparison line for the crypt climate monitor. Its definition
# lives on the model (Climate::Sensor.outdoor_source!) because the outdoor poll
# job ensures it too — a data migration would not reach schema-loaded databases.
# Indoor Govee sensors are not seeded: they arrive through Discover, which reads
# the real device list off the Govee API.
Climate::Sensor.outdoor_source!
seed_puts("Climate outdoor source seeded")
