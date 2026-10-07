require "test_helper"

class Climate::MailboxPollJobTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  EXPORT = "﻿Timestamp,Temperature_Celsius,Relative_Humidity\n" \
           "2026-08-06 09:22:00,14.6,83.7\n" \
           "2026-08-06 09:37:00,14.4,84.1\n".freeze

  # Stands in for Graph::MailboxClient: queued messages, recorded side effects.
  class FakeMailbox
    Message = Struct.new(:id, :from_address, :subject, :body_text, keyword_init: true)

    attr_reader :processed, :attachment_requests

    def initialize(messages: {}, attachments: {}, bodies: {}, sender: "govee@example.com")
      @messages = messages
      @attachments = attachments
      @bodies = bodies
      @sender = sender
      @processed = []
      @attachment_requests = []
    end

    def unread_messages
      @messages.map do |id, subject|
        Message.new(id: id, subject: subject, from_address: @sender, body_text: @bodies.fetch(id, ""))
      end
    end

    def attachments(id)
      @attachment_requests << id
      raise @attachments[id] if @attachments[id].is_a?(Exception)

      @attachments.fetch(id, [])
    end

    def mark_read_and_move(id, folder)
      @processed << [ id, folder ]
    end
  end

  def csv_attachment(filename: "export.csv", body: EXPORT, content_type: "text/csv")
    { filename: filename, content_type: content_type, bytes: body }
  end

  ENV_KEYS = %w[CLIMATE_MAILBOX REIMBURSEMENTS_AZURE_TENANT_ID REIMBURSEMENTS_AZURE_CLIENT_ID
                REIMBURSEMENTS_AZURE_CLIENT_SECRET].freeze

  setup do
    @original_builder = Climate::MailboxPollJob.mailbox_builder
    @original_env = ENV.to_h.slice(*ENV_KEYS)
    ENV.update(ENV_KEYS.zip(%w[climate@example.com tenant client secret]).to_h)
  end

  teardown do
    Climate::MailboxPollJob.mailbox_builder = @original_builder
    ENV_KEYS.each { |key| ENV.delete(key) }
    ENV.update(@original_env)
  end

  def use_mailbox(attachment = csv_attachment, **options)
    fake = FakeMailbox.new(messages: { "1" => "Govee export" }, attachments: { "1" => [ attachment ] }, **options)
    Climate::MailboxPollJob.mailbox_builder = -> { fake }
    fake
  end

  test "no-ops when no climate mailbox is configured" do
    ENV.delete("CLIMATE_MAILBOX")
    create_climate_sensor
    fake = use_mailbox

    Climate::MailboxPollJob.perform_now

    assert_empty fake.processed
  end

  test "imports a CSV against the only sensor, then files the message" do
    sensor = create_climate_sensor(display_name: "Crypt north")
    fake = use_mailbox

    assert_difference -> { sensor.readings.count }, 2 do
      Climate::MailboxPollJob.perform_now
    end

    assert_equal [ [ "1", :processed ] ], fake.processed
  end

  test "with more than one sensor the mail stays unread and the ambiguity is reported once a day" do
    # Govee's email names no device, so two sensors leave nothing to resolve on.
    Rails.cache.delete(Climate::MailboxPollJob::AMBIGUOUS_ALERT_KEY)
    north = create_climate_sensor(display_name: "Crypt north")
    south = create_climate_sensor(display_name: "Crypt south")
    fake = nil

    notices = capture_honeybadger_notices do
      3.times do
        fake = use_mailbox
        Climate::MailboxPollJob.perform_now
      end
    end

    assert_equal 1, notices.size
    assert_empty fake.processed
    assert_equal 0, north.readings.count
    assert_equal 0, south.readings.count
  end

  # What Govee's scheduled export sends, with no attachment, on a day the
  # sensor never reached its cloud (the bodyPreview Graph returns, verbatim).
  NO_DATA_BODY = "Dear customer, No data in the time period you've chosen. Please choose another " \
                 "time period and export the data. Govee Home! This email was sent automatically by"

  test "files Govee's no-data notice instead of leaving it unread for every poll" do
    create_climate_sensor
    fake = use_mailbox(bodies: { "1" => NO_DATA_BODY }, sender: "no-reply@govee.com")

    Climate::MailboxPollJob.perform_now

    assert_equal [ [ "1", :processed ] ], fake.processed
    assert_empty fake.attachment_requests, "a no-data notice has nothing to fetch"
  end

  test "a message with no CSV stays unread unless it is Govee's no-data notice" do
    create_climate_sensor

    [ [ "govee@example.com", "" ],
      [ "someone@example.com", NO_DATA_BODY ],
      [ "no-reply@govee.com", "Your export is ready" ] ].each do |sender, body|
      fake = use_mailbox(attachments: {}, bodies: { "1" => body }, sender: sender)

      Climate::MailboxPollJob.perform_now

      assert_empty fake.processed, [ sender, body ].inspect
    end
  end

  test "ignores a non-CSV attachment" do
    create_climate_sensor
    fake = use_mailbox({ filename: "logo.png", content_type: "image/png", bytes: "x" })

    Climate::MailboxPollJob.perform_now

    assert_empty fake.processed
  end

  test "accepts a CSV sent as text/plain" do
    sensor = create_climate_sensor
    use_mailbox(csv_attachment(content_type: "text/plain; charset=utf-8"))

    Climate::MailboxPollJob.perform_now

    assert_equal 2, sensor.readings.count
  end

  test "leaves an unreadable CSV unread rather than importing nothing silently" do
    create_climate_sensor
    fake = use_mailbox(csv_attachment(body: "Timestamp,Temperature,Relative_Humidity\n2026-08-06 09:22:00,14,83\n"))

    Climate::MailboxPollJob.perform_now

    assert_empty fake.processed
    assert_equal 0, Climate::Reading.count
  end

  test "one bad message does not stop the next being imported" do
    sensor = create_climate_sensor(display_name: "Crypt north")
    fake = use_mailbox(messages: { "1" => "Broken", "2" => "Govee export" },
                       attachments: { "1" => RuntimeError.new("boom"), "2" => [ csv_attachment ] })

    notices = capture_honeybadger_notices { Climate::MailboxPollJob.perform_now }

    assert_equal 1, notices.size
    assert_equal 2, sensor.readings.count
    assert_equal [ "2" ], fake.processed.map(&:first)
  end

  test "never imports against the outdoor feed" do
    # The only sensor here, but not a Govee one: a crypt file on the comparison
    # line would corrupt it.
    outdoor = outdoor_climate_sensor
    fake = use_mailbox

    Climate::MailboxPollJob.perform_now

    assert_equal 0, outdoor.readings.count
    assert_empty fake.processed
  end
end
