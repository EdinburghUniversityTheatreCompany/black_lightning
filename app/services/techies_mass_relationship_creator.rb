class TechiesMassRelationshipCreator
    def create_relationships(relationships_data)
      ActiveRecord::Base.transaction do
        relationships_data.split("\n").each do |relationship|
          # Sanitise the data
          parent_data, child_data = relationship.strip.split(">").map(&:strip)
          parent_names = parent_data.split(",").map(&:strip)
          child_names = child_data.split(",").map(&:strip)

          # Find or create all children and parents.
          parents = parent_names.map { |name| Techie.find_or_create_by(name: name) }
          children = child_names.map { |name| Techie.find_or_create_by(name: name) }

          # And link them together.
          parents.each do |parent|
            parent.children << children
          end
        end
      end
    end
end
