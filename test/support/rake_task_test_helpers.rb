# Runs a real rake task from a test, so one-off maintenance tasks (backfills,
# rollout steps) can be covered like any other code instead of being trusted.
#
# Rake task definitions aren't loaded in the test environment, and loading them
# twice re-appends every task's actions, so the load is memoized here. Each
# invoke re-enables the task first: Rake remembers that a task already ran, so
# without this a second test would silently invoke nothing.
require "rake"

module RakeTaskTestHelpers
  @tasks_loaded = false

  class << self
    def load_tasks_once
      return if @tasks_loaded

      Rails.application.load_tasks
      @tasks_loaded = true
    end
  end

  # Returns whatever the task wrote to stdout, so a test can assert on the
  # progress/summary output without it polluting the suite's own.
  def run_rake_task(name, *args)
    RakeTaskTestHelpers.load_tasks_once
    task = Rake::Task[name]
    task.reenable
    stdout, = capture_io { task.invoke(*args) }
    stdout
  end
end
