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
  validates :name, presence: true, length: { in: 1..32 }
  validates :name, uniqueness: { case_sensitive: false }

  has_and_belongs_to_many :parents, class_name: 'Techie', foreign_key: 'child_id', association_foreign_key: 'techie_id', join_table: 'children_techies'

  has_and_belongs_to_many :children, class_name: 'Techie', foreign_key: 'techie_id', association_foreign_key: 'child_id', join_table: 'children_techies'

  accepts_nested_attributes_for :children, :parents, reject_if: :all_blank, allow_destroy: true

  default_scope -> { order('name ASC') }

  # Because the relations are quite complicated, this breaks without this code.
  def children_attributes=(attributes)
    cycle_through_attributes(attributes, children)
  end

  def parents_attributes=(attributes)
    cycle_through_attributes(attributes, parents)
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
