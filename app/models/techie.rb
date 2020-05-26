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
##
class Techie < ApplicationRecord
  validates :name, presence: true, length: { in: 1..32 }

  has_and_belongs_to_many :parents, class_name: 'Techie', foreign_key: 'child_id', association_foreign_key: 'techie_id', join_table: 'children_techies'

  has_and_belongs_to_many :children, class_name: 'Techie', foreign_key: 'techie_id', association_foreign_key: 'child_id', join_table: 'children_techies'

  accepts_nested_attributes_for :children, :parents, reject_if: :all_blank, allow_destroy: true

  default_scope -> { order('name ASC') }

  # Because the relations are quite complicated, this breaks without this code.
  def children_attributes=(attributes)
    attributes.each do |attribute|
      techie = Techie.find(attribute[1][:id])

      children << techie unless children.all.include?(techie)

      children.delete(techie) if attribute[1][:_destroy] == '1'
    end
  end

  def parents_attributes=(attributes)
    attributes.each do |attribute|
      techie = Techie.find(attribute[1][:id])

      parents << techie unless parents.all.include?(techie)

      parents.delete(techie) if attribute[1][:_destroy] == '1'
    end
  end
end
