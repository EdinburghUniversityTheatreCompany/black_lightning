# == Schema Information
#
# Table name: admin_editable_blocks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *content*::    <tt>text</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *admin_page*:: <tt>boolean</tt>
# *group*::      <tt>string(255)</tt>
#--
# == Schema Information End
#++

##
# Represents a section in a page that can be edited using the Admin pages.
#
# IMPORTANT: The admin_page property is used to ensure that visitors that are not logged in
# cannot access any Attachment belonging to this block.
#
# == Schema Information
#
# Table name: admin_editable_blocks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *name*::       <tt>string(255)</tt>
# *content*::    <tt>text</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *admin_page*:: <tt>boolean</tt>
# *group*::      <tt>string(255)</tt>
#--
# == Schema Information End
#++
##
class Admin::EditableBlock < ActiveRecord::Base
  resourcify

  validates :name, :presence => true, :uniqueness => true

  has_many :attachments, :class_name => "::Attachment"
  accepts_nested_attributes_for :attachments, :reject_if => :all_blank, :allow_destroy => true

  attr_accessible :content, :name, :attachments, :attachments_attributes, :admin_page, :group

  def self.groups
    select('`group`').uniq.map { |g| g.group }
  end
end
