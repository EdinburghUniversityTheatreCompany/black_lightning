namespace :jobs do
  desc "Migrate existing delayed_job staffing reminders to ActiveJob/SolidQueue"
  task migrate_staffing_reminders: :environment do
    puts "Starting migration of staffing reminder jobs..."

    migrated_count = 0
    skipped_count = 0
    error_count = 0

    # Find all delayed jobs that are staffing reminder jobs
    delayed_jobs = Delayed::Job.where("handler LIKE ?", "%Admin::Staffing%send_reminder%")

    puts "Found #{delayed_jobs.count} delayed staffing reminder jobs to migrate"

    delayed_jobs.find_each do |delayed_job|
      begin
        # Parse the delayed job handler to extract the staffing ID
        handler_yaml = YAML.load(delayed_job.handler)

        # The handler should be a Delayed::PerformableMethod
        if handler_yaml.is_a?(Delayed::PerformableMethod)
          object = handler_yaml.object
          method_name = handler_yaml.method_name

          if object.is_a?(Admin::Staffing) && method_name.to_s == "send_reminder"
            staffing = object

            # Check if this staffing still exists and hasn't been executed
            if staffing.persisted? && !staffing.reminder_job_executed?

              # Schedule the new ActiveJob with the same timing
              scheduled_time = delayed_job.run_at

              if scheduled_time > Time.current
                puts "Migrating job for Staffing #{staffing.id} (#{staffing.show_title}) scheduled for #{scheduled_time}"

                # Create the new ActiveJob
                job = StaffingReminderJob.set(wait_until: scheduled_time).perform_later(staffing.id)

                # Update the staffing record with the new job ID
                staffing.update_columns(
                  scheduled_job_id: job.job_id,
                  reminder_job_executed: false,
                  reminder_job_id: nil  # Clear the old delayed job reference
                )

                # Remove the old delayed job
                delayed_job.destroy

                migrated_count += 1
              else
                puts "Skipping expired job for Staffing #{staffing.id} - was scheduled for #{scheduled_time}"
                delayed_job.destroy
                skipped_count += 1
              end
            else
              puts "Skipping job for Staffing #{staffing.id} - staffing not found or already executed"
              delayed_job.destroy
              skipped_count += 1
            end
          else
            puts "Skipping non-staffing reminder job: #{delayed_job.id}"
            skipped_count += 1
          end
        else
          puts "Skipping job with unrecognized handler format: #{delayed_job.id}"
          skipped_count += 1
        end

      rescue => e
        puts "Error processing delayed job #{delayed_job.id}: #{e.message}"
        error_count += 1
      end
    end

    puts "\nMigration complete!"
    puts "Migrated: #{migrated_count} jobs"
    puts "Skipped: #{skipped_count} jobs"
    puts "Errors: #{error_count} jobs"

    if error_count > 0
      puts "\nSome jobs could not be migrated. Check the output above for details."
      exit 1
    end
  end

  desc "Show status of job migration"
  task migration_status: :environment do
    delayed_staffing_jobs = Delayed::Job.where("handler LIKE ?", "%Admin::Staffing%send_reminder%").count

    # Count staffing jobs by checking job IDs that exist in both tables
    scheduled_job_ids = Admin::Staffing.where.not(scheduled_job_id: nil).pluck(:scheduled_job_id)
    active_job_staffing_jobs = SolidQueue::Job.where(active_job_id: scheduled_job_ids).count

    staffings_with_scheduled_jobs = Admin::Staffing.where.not(scheduled_job_id: nil).count

    puts "Job Migration Status:"
    puts "====================="
    puts "Remaining delayed_job staffing reminders: #{delayed_staffing_jobs}"
    puts "Active staffing reminder jobs in Solid Queue: #{active_job_staffing_jobs}"
    puts "Staffings with scheduled job IDs: #{staffings_with_scheduled_jobs}"

    if delayed_staffing_jobs > 0
      puts "\nTo migrate remaining jobs, run: rails jobs:migrate_staffing_reminders"
    else
      puts "\nAll staffing reminder jobs have been migrated!"
    end
  end
end
