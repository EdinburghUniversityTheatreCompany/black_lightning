class Techie < ActiveRecord::Base
  attr_accessible :name
  has_and_belongs_to_many :children, :class_name => "Techie", :foreign_key => "techie_id", :association_foreign_key => "child_id", :join_table => "children_techies"
  has_and_belongs_to_many :parents, :class_name => "Techie", :foreign_key => "child_id", :association_foreign_key => "techie_id", :join_table => "children_techies"
end
