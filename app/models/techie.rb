class Techie < ActiveRecord::Base
  attr_accessible :name
  has_and_belongs_to_many :children, :class_name => "Techie", :association_foreign_key => "child_id", :join_table => "children_techies"
end
