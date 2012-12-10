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
  attr_accessible :name
  has_and_belongs_to_many :children, :class_name => "Techie", :foreign_key => "techie_id", :association_foreign_key => "child_id", :join_table => "children_techies"
  has_and_belongs_to_many :parents, :class_name => "Techie", :foreign_key => "child_id", :association_foreign_key => "techie_id", :join_table => "children_techies"
end
