# == Schema Information
#
# Table name: admin_proposals_calls
#
# *id*::         <tt>integer, not null, primary key</tt>
# *deadline*::   <tt>datetime</tt>
# *name*::       <tt>string(255)</tt>
# *open*::       <tt>boolean</tt>
# *created_at*:: <tt>datetime, not null</tt>
# *updated_at*:: <tt>datetime, not null</tt>
# *archived*::   <tt>boolean</tt>
#--
# == Schema Information End
#++

class Admin::Proposals::Call < ActiveRecord::Base
  has_many :questions, :as => :questionable, :dependent => :destroy
  has_many :proposals, :class_name => "Admin::Proposals::Proposal"

  scope :open, :conditions => { :open => true }

  accepts_nested_attributes_for :questions, :reject_if => :all_blank, :allow_destroy => true

  validates :deadline, :name, :presence => true

  attr_accessible :deadline, :name, :open, :archived, :questions, :questions_attributes

  def archive
    self.open = false

    self.archived = true

    self.save
  end
end
