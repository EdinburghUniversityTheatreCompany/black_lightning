namespace :strays do
  task :list, [:model] => :environment do |t, args|
    klass_name = args[:model]
    klass = klass_name.constantize

    associations = klass.reflect_on_all_associations

    associations.each do |a|
      next unless a.belongs_to?

      puts "#{klass_name.pluralize} with #{a.name.to_s.pluralize} that don't exist"

      strays = klass.where("#{a.name.to_s}_id is not null").select { |k| k.send(a.name).nil? }
      strays.each do |s|
        puts "  #{s.id} expected #{a.name} with id #{s.send(a.name.to_s + "_id")}"
      end
    end
  end

  task :remove, [:model] => :environment do |t, args|
    klass_name = args[:model]
    klass = klass_name.constantize

    associations = klass.reflect_on_all_associations

    associations.each do |a|
      next unless a.belongs_to?

      puts "Removing #{klass_name.pluralize} with #{a.name.to_s.pluralize} that don't exist"

      strays = klass.where("#{a.name.to_s}_id is not null").select { |k| k.send(a.name).nil? }
      strays.each do |s|
        s.delete
        puts "  #{s.id} deleted, as #{a.name} with id #{s.send(a.name.to_s + "_id")} doesn't exist"
      end
    end
  end
end