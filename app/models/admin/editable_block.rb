# == Schema Information
#
# Table name: admin_editable_blocks
#
#  id         :integer          not null, primary key
#  name       :string(255)
#  content    :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  admin_page :boolean
#  group      :string(255)
#

class Admin::EditableBlock < ActiveRecord::Base
  resourcify

  validates :name, :presence => true, :uniqueness => true

  has_many :attachments, :class_name => "::Attachment"
  accepts_nested_attributes_for :attachments, :reject_if => :all_blank

  attr_accessible :content, :name, :attachments, :attachments_attributes, :admin_page, :group
end
