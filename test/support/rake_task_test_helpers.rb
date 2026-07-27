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
  #
  # Deliberately swaps $stdout rather than using Minitest's capture_io. Under
  # `parallelize`, capture_io synchronizes on a shared mutex, so a caller that
  # wrapped this in its own capture_io -- the only way to read the output of a
  # task that aborts, since capture_io drops its buffer when the block raises --
  # locked that mutex twice on one thread and died with "deadlock; recursive
  # locking". Keeping the buffer here means a task that raises SystemExit still
  # leaves its output readable via #last_rake_output, so no caller has to nest.
  def run_rake_task(name, *args)
    RakeTaskTestHelpers.load_tasks_once
    task = Rake::Task[name]
    task.reenable

    buffer = StringIO.new
    original_stdout = $stdout
    $stdout = buffer
    begin
      task.invoke(*args)
    ensure
      $stdout = original_stdout
      @last_rake_output = buffer.string
    end

    @last_rake_output
  end

  # stdout of the most recent run_rake_task, including when it raised.
  def last_rake_output
    @last_rake_output.to_s
  end
end
