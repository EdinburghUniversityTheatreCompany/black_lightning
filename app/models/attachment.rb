class Attachment < ActiveRecord::Base
  belongs_to :editable_block, :class_name => "Admin::EditableBlock"

  validates :name, :presence => true, :uniqueness => true

  has_attached_file :file

  attr_accessible :name, :file
end
