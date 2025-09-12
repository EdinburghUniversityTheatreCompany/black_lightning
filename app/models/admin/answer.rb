##
# Represents an answer to an Admin::Question.
#
# May have an attached file if the response_type requires it.
#
# == Schema Information
#
# Table name: admin_answers
#
# *id*::                <tt>integer, not null, primary key</tt>
# *question_id*::       <tt>integer</tt>
# *answerable_id*::     <tt>integer</tt>
# *answer*::            <tt>text(65535)</tt>
# *created_at*::        <tt>datetime, not null</tt>
# *updated_at*::        <tt>datetime, not null</tt>
# *answerable_type*::   <tt>string(255)</tt>
# *file_file_name*::    <tt>string(255)</tt>
# *file_content_type*:: <tt>string(255)</tt>
# *file_file_size*::    <tt>integer</tt>
# *file_updated_at*::   <tt>datetime</tt>
#--
# == Schema Information End
#++
class Admin::Answer < ApplicationRecord
  validates :question_id, presence: true

  belongs_to :question, class_name: "Admin::Question"
  belongs_to :answerable, polymorphic: true

  # To hold files, if necessary.
  include AttachmentItem

  default_scope { includes(:question, :attachments) }

  def self.ransackable_attributes(auth_object = nil)
    []
  end
end
