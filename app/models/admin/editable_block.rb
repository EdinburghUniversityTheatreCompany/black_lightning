class Admin::EditableBlock < ActiveRecord::Base
  resourcify

  validates :name, :presence => true, :uniqueness => true

  has_many :attachments, :class_name => "::Attachment"
  accepts_nested_attributes_for :attachments, :reject_if => :all_blank

  attr_accessible :content, :name, :attachments, :attachments_attributes, :admin_page
end
