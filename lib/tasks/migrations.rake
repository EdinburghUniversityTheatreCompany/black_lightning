require "#{Rails.root}/lib/tasks/logic/migrations"

namespace :migrations do
  # I don't have any better name, but this is just to fix a failed migration.
  # :nocov:
  desc 'Fixes the editing deadline on proposals by defaulting to the submission deadline'
  task fix_editing_deadline: :environment do
    amount = Tasks::Logic::Migrations.fix_editing_deadline
    puts "Fixed the submission deadline for #{amount} calls."
  end
  
  namespace :active_storage do
    desc 'Migrate the Venue image from Paperclip to ActiveStorage'
    task venue_image: :environment do
      Tasks::Logic::Migrations.venue_image
      p 'Migrated all Venue images.'
    end

    desc 'Migrate the Venue image from Paperclip to ActiveStorage'
    task user_avatar: :environment do
      model = User
      attachments = ['avatar']

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p 'Migrated all User avatars.'
    end

    desc 'Migrate the News image from Paperclip to ActiveStorage'
    task news_image: :environment do
      model = News
      attachments = ['image']

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p 'Migrated all News images.'
    end

    desc 'Migrate the Event image from Paperclip to ActiveStorage'
    task event_image: :environment do
      model = Event
      attachments = ['image']

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p 'Migrated all Event images.'
    end
  end
  # :nocov:
end
