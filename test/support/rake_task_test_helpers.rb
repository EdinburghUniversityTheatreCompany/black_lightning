# Runs a real rake task from a test, so maintenance tasks (backfills, rollout steps) get covered.
# Loading the tasks twice re-appends every action, so they load once. Rake remembers that a
# task already ran, so each invoke re-enables it, or a second test would silently invoke nothing.
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

  # Returns the task's stdout. Swaps $stdout instead of using capture_io: its shared mutex
  # deadlocks ("recursive locking") when nested under `parallelize`, and it drops its buffer
  # when the block raises. Keeping the buffer for #last_rake_output means no caller nests.
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
