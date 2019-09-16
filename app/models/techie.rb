##
# Represents a techie that will be an entry in the techie families graph.
#
#--
# TODO: Currently no way to add instances of this model.
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
class Techie < ActiveRecord::Base
  has_and_belongs_to_many :children, class_name: 'Techie', foreign_key: 'techie_id', association_foreign_key: 'child_id', join_table: 'children_techies'
  has_and_belongs_to_many :parents, class_name: 'Techie', foreign_key: 'child_id', association_foreign_key: 'techie_id', join_table: 'children_techies'

  accepts_nested_attributes_for :children, :parents, reject_if: :all_blank, allow_destroy: true

  default_scope -> { order('name ASC') }

  # Without these, this was breaking - I don't know why.
  def children_attributes=(attributes)
    attributes.each do |attribute|
      techie = Techie.find(attribute[1][:id])

      unless children.all.include?(techie)
        children << techie
      end

      if attribute[1][:_destroy] == '1'
        children.delete(techie)
      end
    end
  end

  def parents_attributes=(attributes)
    attributes.each do |attribute|
      Rails.logger.debug attribute
      techie = Techie.find(attribute[1][:id])

      unless parents.all.include?(techie)
        parents << techie
      end

      if attribute[1][:_destroy] == '1'
        parents.delete(techie)
      end
    end
  end
end
