require "test_helper"

class Pretix::SyncPerformancesJobTest < ActiveSupport::TestCase
  # Records which events it was asked about, and can be told to fail for one of
  # them. This suite has no mocking library.
  class FakeSync
    attr_reader :events

    def initialize(failing_slugs: [])
      @failing_slugs = failing_slugs
      @events = []
    end

    def call(event)
      @events << event
      raise Pretix::Client::NotFoundError, "no such series" if @failing_slugs.include?(event.pretix_slug)

      Pretix::PerformanceSync::Result.new(created: 1, updated: 0, destroyed: 0, kept: 0,
                                          skipped: 0, emptied_series: false)
    end
  end

  setup do
    @sync = FakeSync.new
    Pretix::SyncPerformancesJob.sync_builder = -> { @sync }
    Pretix::SyncPerformancesJob.settings = Class.new { def self.configured? = true }
  end

  teardown do
    Pretix::SyncPerformancesJob.sync_builder = Pretix::SyncPerformancesJob::DEFAULT_SYNC_BUILDER
    Pretix::SyncPerformancesJob.settings = Pretix::Settings
  end

  def event(slug:, sync: true, start_date: Date.current, end_date: Date.current + 3)
    FactoryBot.create(:show, slug: slug, start_date: start_date, end_date: end_date,
                             pretix_sync_performances: sync)
  end

  test "syncs the events with the box ticked" do
    ticked = event(slug: "hamlet")
    event(slug: "macbeth", sync: false)

    Pretix::SyncPerformancesJob.perform_now

    assert_equal [ ticked ], @sync.events
  end

  test "leaves a finished run alone" do
    event(slug: "last-year", start_date: 1.year.ago.to_date, end_date: 1.year.ago.to_date + 3)

    Pretix::SyncPerformancesJob.perform_now

    assert_empty @sync.events
  end

  test "a run still on tonight is not finished" do
    tonight = event(slug: "tonight", start_date: Date.current - 3, end_date: Date.current)

    Pretix::SyncPerformancesJob.perform_now

    assert_equal [ tonight ], @sync.events
  end


  # One producer's wrong slug must not cost every other show its sync.
  test "one failing event does not stop the rest" do
    @sync = FakeSync.new(failing_slugs: [ "broken" ])
    Pretix::SyncPerformancesJob.sync_builder = -> { @sync }
    event(slug: "broken")
    working = event(slug: "working")

    assert_nothing_raised { Pretix::SyncPerformancesJob.perform_now }

    assert_includes @sync.events, working
  end

  test "does nothing without pretix credentials" do
    Pretix::SyncPerformancesJob.settings = Class.new { def self.configured? = false }
    event(slug: "hamlet")

    Pretix::SyncPerformancesJob.perform_now

    assert_empty @sync.events
  end
end
