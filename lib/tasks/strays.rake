# From paperclip source.
# This will very likely not work anymore after we upgraded to ActiveStorage.

module Paperclip
  # :nocov:
  module Task
    def self.obtain_attachments(klass)
      klass = Paperclip.class_for(klass.to_s)
      name = ENV['ATTACHMENT'] || ENV['attachment']
      fail "Class #{klass.name} has no attachments specified" unless klass.respond_to?(:attachment_definitions)
      if !name.blank? && klass.attachment_definitions.keys.map(&:to_s).include?(name.to_s)
        [name]
      else
        klass.attachment_definitions.keys
      end
    end
  end
  # :nocov:
end

namespace :strays do
  # :nocov:
  task :list, [:model] => :environment do |_t, args|
    klass_name = args[:model]
    klass = klass_name.constantize

    associations = klass.reflect_on_all_associations

    associations.each do |a|
      next unless a.belongs_to?

      p "#{klass_name.pluralize} with #{a.name.to_s.pluralize} that don't exist"

      strays = klass.where("#{a.name}_id is not null").select { |k| k.send(a.name).nil? }
      strays.each do |s|
        p "  #{s.id} expected #{a.name} with id #{s.send(a.name.to_s + '_id')}"
      end
    end
  end

  task :remove, [:model] => :environment do |_t, args|
    klass_name = args[:model]
    klass = klass_name.constantize

    associations = klass.reflect_on_all_associations

    associations.each do |a|
      next unless a.belongs_to?

      p "Removing #{klass_name.pluralize} with #{a.name.to_s.pluralize} that don't exist"

      strays = klass.where("#{a.name}_id is not null").select { |k| k.send(a.name).nil? }
      strays.each do |s|
        s.delete
        p "  #{s.id} deleted, as #{a.name} with id #{s.send(a.name.to_s + '_id')} doesn't exist"
      end
    end
  end

  task :list_missing_files, [:model] => :environment do |_t, args|
    klass_name = args[:model]
    klass = klass_name.constantize
    attachments = Paperclip::Task.obtain_attachments(klass_name)

    klass.all.each do |k|
      attachments.each do |a|
        attachment = k.send(a)
        next unless attachment.exists?

        missing = []

        attachment.styles.each do |s|
          unless File.exist?(attachment.path(s[0]))
            missing << s[0]
          end
        end

        if !File.exist?(attachment.path)
          p "#{klass_name} #{k.id} is missing its original file."
        elsif missing == attachment.styles.map { |s| s[0] }
          p "#{klass_name} #{k.id} is missing all styles for attachment #{a} and should be reprocessed."
        elsif missing.count > 0
          p "#{klass_name} #{k.id} is missing styles #{missing} for attachment #{a} and should be reprocessed."
        end
      end
    end
  end

  task :resolve_missing_files, [:model] => :environment do |_t, args|
    klass_name = args[:model]
    klass = klass_name.constantize
    attachments = Paperclip::Task.obtain_attachments(klass_name)

    klass.all.each do |k|
      attachments.each do |a|
        attachment = k.send(a)
        next unless attachment.exists?

        missing = []

        attachment.styles.each do |s|
          unless File.exist?(attachment.path(s[0]))
            missing << s[0]
          end
        end

        if !File.exist?(attachment.path)
          p "#{klass_name} #{k.id} is missing its original file. Setting file to nil."
          attachment.clear
          k.save!
        elsif missing == attachment.styles.map { |s| s[0] }
          p "#{klass_name} #{k.id} is missing all styles for attachment #{a} and will be reprocessed."
          attachment.reprocess!
        elsif missing.count > 0
          p "#{klass_name} #{k.id} is missing styles #{missing} for attachment #{a} and will be reprocessed."
          attachment.reprocess!
        end
      end
    end
  end
  # :nocov:
end

