require "test_helper"

class Climate::MailboxPollJobTest < ActiveSupport::TestCase
  include ClimateTestHelpers

  EXPORT = "﻿Timestamp,Temperature_Celsius,Relative_Humidity\n" \
           "2026-08-06 09:22:00,14.6,83.7\n" \
           "2026-08-06 09:37:00,14.4,84.1\n".freeze

  # Stands in for Graph::MailboxClient: queued messages, recorded side effects.
  class FakeMailbox
    Message = Struct.new(:id, :from_address, :subject, :body_text, keyword_init: true)

    attr_reader :processed, :read

    def initialize(messages: {}, attachments: {})
      @messages = messages
      @attachments = attachments
      @processed = []
      @read = []
    end

    def unread_messages
      @messages.map { |id, subject| Message.new(id: id, subject: subject, from_address: "govee@example.com") }
    end

    def attachments(id) = @attachments.fetch(id, [])

    def mark_read_and_move(id, folder)
      @read << id
      @processed << [ id, folder ]
    end
  end

  def csv_attachment(filename: "export.csv", body: EXPORT, content_type: "text/csv")
    { filename: filename, content_type: content_type, bytes: body }
  end

  setup do
    @original_builder = Climate::MailboxPollJob.mailbox_builder
    @original_mailbox = ENV.fetch("CLIMATE_MAILBOX", nil)
    @original_tenant = ENV.fetch("REIMBURSEMENTS_AZURE_TENANT_ID", nil)
    ENV["CLIMATE_MAILBOX"] = "climate@example.com"
    ENV["REIMBURSEMENTS_AZURE_TENANT_ID"] = "tenant"
    ENV["REIMBURSEMENTS_AZURE_CLIENT_ID"] = "client"
    ENV["REIMBURSEMENTS_AZURE_CLIENT_SECRET"] = "secret"
  end

  teardown do
    Climate::MailboxPollJob.mailbox_builder = @original_builder
    @original_mailbox.nil? ? ENV.delete("CLIMATE_MAILBOX") : ENV["CLIMATE_MAILBOX"] = @original_mailbox
    if @original_tenant.nil?
      %w[REIMBURSEMENTS_AZURE_TENANT_ID REIMBURSEMENTS_AZURE_CLIENT_ID
         REIMBURSEMENTS_AZURE_CLIENT_SECRET].each { |key| ENV.delete(key) }
    end
  end

  def use_mailbox(fake)
    Climate::MailboxPollJob.mailbox_builder = -> { fake }
    fake
  end

  test "no-ops when no climate mailbox is configured" do
    ENV.delete("CLIMATE_MAILBOX")
    create_climate_sensor
    fake = use_mailbox(FakeMailbox.new(messages: { "1" => "Govee export" }))

    Climate::MailboxPollJob.perform_now

    assert_empty fake.read
  end

  test "imports a CSV attachment against the only sensor" do
    sensor = create_climate_sensor(display_name: "Crypt north")
    use_mailbox(FakeMailbox.new(messages: { "1" => "Your Govee data export" },
                                attachments: { "1" => [ csv_attachment ] }))

    assert_difference -> { sensor.readings.count }, 2 do
      Climate::MailboxPollJob.perform_now
    end
  end

  test "marks the message read and moves it once imported" do
    create_climate_sensor
    fake = use_mailbox(FakeMailbox.new(messages: { "1" => "Govee export" },
                                       attachments: { "1" => [ csv_attachment ] }))

    Climate::MailboxPollJob.perform_now

    assert_equal [ [ "1", :processed ] ], fake.processed
  end

  test "leaves a message unread when more than one sensor exists" do
    # Govee's email identifies no device, so with two sensors there is nothing
    # to resolve on. Guessing would file one wall's readings under another.
    north = create_climate_sensor(display_name: "Crypt north")
    south = create_climate_sensor(display_name: "Crypt south")
    fake = use_mailbox(FakeMailbox.new(messages: { "1" => "Your data export" },
                                       attachments: { "1" => [ csv_attachment ] }))

    Climate::MailboxPollJob.perform_now

    assert_empty fake.read
    assert_equal 0, north.readings.count
    assert_equal 0, south.readings.count
  end

  test "reports the ambiguity rather than letting mail pile up unnoticed" do
    Rails.cache.delete(Climate::MailboxPollJob::AMBIGUOUS_ALERT_KEY)
    create_climate_sensor(display_name: "Crypt north")
    create_climate_sensor(display_name: "Crypt south")
    use_mailbox(FakeMailbox.new(messages: { "1" => "Your data export" },
                                attachments: { "1" => [ csv_attachment ] }))

    notices = capture_honeybadger_notices { Climate::MailboxPollJob.perform_now }

    assert_equal 1, notices.size
  end

  test "the ambiguity alert is sent once a day, not once a cycle" do
    Rails.cache.delete(Climate::MailboxPollJob::AMBIGUOUS_ALERT_KEY)
    create_climate_sensor(display_name: "Crypt north")
    create_climate_sensor(display_name: "Crypt south")

    notices = capture_honeybadger_notices do
      3.times do
        use_mailbox(FakeMailbox.new(messages: { "1" => "Your data export" },
                                    attachments: { "1" => [ csv_attachment ] }))
        Climate::MailboxPollJob.perform_now
      end
    end

    assert_equal 1, notices.size
  end

  test "leaves a message with no CSV attachment unread" do
    create_climate_sensor
    fake = use_mailbox(FakeMailbox.new(messages: { "1" => "Just a note" }, attachments: { "1" => [] }))

    Climate::MailboxPollJob.perform_now

    assert_empty fake.read
  end

  test "ignores a non-CSV attachment" do
    create_climate_sensor
    fake = use_mailbox(FakeMailbox.new(
                         messages: { "1" => "Govee export" },
                         attachments: { "1" => [ { filename: "logo.png", content_type: "image/png", bytes: "x" } ] }
                       ))

    Climate::MailboxPollJob.perform_now

    assert_empty fake.read
  end

  test "accepts a CSV sent as text/plain" do
    sensor = create_climate_sensor
    use_mailbox(FakeMailbox.new(messages: { "1" => "Govee export" },
                                attachments: { "1" => [ csv_attachment(content_type: "text/plain; charset=utf-8") ] }))

    Climate::MailboxPollJob.perform_now

    assert_equal 2, sensor.readings.count
  end

  test "leaves an unreadable CSV unread rather than importing nothing silently" do
    create_climate_sensor
    fake = use_mailbox(FakeMailbox.new(
                         messages: { "1" => "Govee export" },
                         attachments: { "1" => [ csv_attachment(body: "Timestamp,Temperature,Relative_Humidity\n2026-08-06 09:22:00,14,83\n") ] }
                       ))

    Climate::MailboxPollJob.perform_now

    assert_empty fake.read
    assert_equal 0, Climate::Reading.count
  end

  test "re-importing the same export writes no new rows" do
    sensor = create_climate_sensor
    2.times do
      use_mailbox(FakeMailbox.new(messages: { "1" => "Govee export" },
                                  attachments: { "1" => [ csv_attachment ] }))
      Climate::MailboxPollJob.perform_now
    end

    assert_equal 2, sensor.readings.count
  end

  test "one bad message does not stop the next being imported" do
    sensor = create_climate_sensor(display_name: "Crypt north")
    fake = FakeMailbox.new(messages: { "1" => "Broken", "2" => "Govee export" },
                           attachments: { "1" => [ csv_attachment(body: "nonsense") ],
                                          "2" => [ csv_attachment ] })
    use_mailbox(fake)

    Climate::MailboxPollJob.perform_now

    assert_equal 2, sensor.readings.count
    assert_equal [ "2" ], fake.read
  end

  test "never imports against the outdoor feed" do
    # It is the only sensor here, but it is not a Govee one — a crypt file
    # landing on the comparison line would corrupt it.
    outdoor = outdoor_climate_sensor
    fake = use_mailbox(FakeMailbox.new(messages: { "1" => "Your data export" },
                                       attachments: { "1" => [ csv_attachment ] }))

    Climate::MailboxPollJob.perform_now

    assert_equal 0, outdoor.readings.count
    assert_empty fake.read
  end
end
