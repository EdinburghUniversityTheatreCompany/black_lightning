namespace :strays do
  # simplecov:disable
  task :list, [ :model ] => :environment do |_t, args|
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

  task :remove, [ :model ] => :environment do |_t, args|
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

  # simplecov:enable
end
