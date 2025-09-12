require "csv"

class Tasks::Logic::Techie
  def self.import(file)
    CSV.foreach(file) do |row|
      parent = Techie.find_or_create_by(name: row[0])

      child = row[1]
      Raise(ArgumentError, "Use a comma (,) as the separator, not a semicolon {;), on row #{row}") if child.nil? && row.includes(";")

      child = Techie.find_or_create_by(name: child)

      parent.children << child
      parent.save
    end
  end
end
