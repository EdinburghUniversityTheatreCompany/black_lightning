require "#{Rails.root}/lib/tasks/logic/migrations_task_logic"

namespace :migrations do
  # I don't have any better name, but this is just to fix a failed migration.
  # :nocov:
  task fix_editing_deadline: :environment do
    amount = MigrationsTaskLogic.fix_editing_deadline
    puts "Fixed the submission deadline for #{amount} calls."
  end
  # :nocov:
end
