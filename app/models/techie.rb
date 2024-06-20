##
# Represents a techie that will be an entry in the techie family tree.
#
#++
#
# == Schema Information
#
# Table name: techies
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
#--
# == Schema Information End
#++
class Techie < ApplicationRecord
  validates :name, presence: true, uniqueness: { case_sensitive: false }

  has_and_belongs_to_many :parents, class_name: 'Techie', foreign_key: 'child_id', association_foreign_key: 'techie_id', join_table: 'children_techies'

  has_and_belongs_to_many :children, class_name: 'Techie', foreign_key: 'techie_id', association_foreign_key: 'child_id', join_table: 'children_techies'

  accepts_nested_attributes_for :children, :parents, reject_if: :all_blank, allow_destroy: true

  normalizes :name, with: -> (name) { name&.strip }

  default_scope -> { order('name ASC') }

  def self.ransackable_attributes(auth_object = nil)
    %w[id name]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[children parents]
  end

  def self.mass_create(relationships_data)
    TechiesMassRelationshipCreator.new.create_relationships(relationships_data)
  end

  # Because the relations are quite complicated, this breaks without this code.
  def children_attributes=(attributes)
    cycle_through_attributes(attributes, children)
  end

  def parents_attributes=(attributes)
    cycle_through_attributes(attributes, parents)
  end

  def get_relatives(amount_of_generations, get_siblings_of_related)
    # Make sure the amount of generations to get is at least one.
    amount_of_generations = 1 if amount_of_generations < 1
    amount_of_generations -= 1
    # Load all techies to cache them.
    Techie.all.includes(:children, :parents).load

    techies = [self]

    techie_parents = [self]
    techie_children = [self]

    (0..amount_of_generations).each do
      techie_parents = techie_parents.to_a.flat_map(&:parents).uniq

      techie_children = techie_children.to_a.flat_map(&:children).uniq

      techies += techie_parents.to_a + techie_children.to_a
    end

    return techies.uniq
  end

  private

  def cycle_through_attributes(attributes, collection)
    attributes.each do |attribute|
      id = attribute[1][:id]
      next if id == ''

      techie = Techie.find(id)

      collection << techie unless collection.all.include?(techie)

      collection.delete(techie) if attribute[1][:_destroy] == '1'
    end
  end
end
