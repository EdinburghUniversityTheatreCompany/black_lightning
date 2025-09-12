require "#{Rails.root}/lib/tasks/logic/migrations"

namespace :migrations do
  # I don't have any better name, but this is just to fix a failed migration.
  # :nocov:
  desc "Fixes the editing deadline on proposals by defaulting to the submission deadline"
  task fix_editing_deadline: :environment do
    amount = Tasks::Logic::Migrations.fix_editing_deadline
    puts "Fixed the submission deadline for #{amount} calls."
  end

  namespace :active_storage do
    desc "Migrate the Venue image from Paperclip to ActiveStorage"
    task venue_image: :environment do
      Tasks::Logic::Migrations.venue_image
      p "Migrated all Venue images."
    end

    desc "Migrate the Venue image from Paperclip to ActiveStorage"
    task user_avatar: :environment do
      model = User
      attachments = [ "avatar" ]

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p "Migrated all User avatars."
    end

    desc "Migrate the News image from Paperclip to ActiveStorage"
    task news_image: :environment do
      model = News
      attachments = [ "image" ]

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p "Migrated all News images."
    end

    desc "Migrate the Event image from Paperclip to ActiveStorage"
    task event_image: :environment do
      model = Event
      attachments = [ "image" ]

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p "Migrated all Event images."
    end

    desc "Migrate the Picture image from Paperclip to ActiveStorage"
    task picture_image: :environment do
      model = Picture
      attachments = [ "image" ]

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p "Migrated all Picture images."
    end

    desc "Migrate the Attachment file from Paperclip to ActiveStorage"
    task attachment_file: :environment do
      model = Attachment
      attachments = [ "file" ]

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p "Migrated all Attachment files."
    end

    desc "Migrate the Answer file from Paperclip to ActiveStorage"
    task answer_file: :environment do
      model = Admin::Answer
      attachments = [ "file" ]

      Tasks::Logic::Migrations.migrate_from_paperclip_to_active_storage(model, attachments)

      p "Migrated all Answer files."
    end
  end
  # :nocov:
end
