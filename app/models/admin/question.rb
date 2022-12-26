##
# Represents questions in the <tt>questionnable</tt> polymorphic association.
#
# Questions have Answers you know.
#
# == Schema Information
#
# Table name: admin_questions
#
# *id*::                <tt>integer, not null, primary key</tt>
# *question_text*::     <tt>text(65535)</tt>
# *response_type*::     <tt>string(255)</tt>
# *created_at*::        <tt>datetime, not null</tt>
# *updated_at*::        <tt>datetime, not null</tt>
# *questionable_id*::   <tt>integer</tt>
# *questionable_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++
class Admin::Question < ApplicationRecord
  validates :question_text, :response_type, presence: true
  
  belongs_to :questionable, polymorphic: true

  has_many :answers, class_name: 'Admin::Answer', dependent: :destroy

  ##
  # Defines the possible response types.
  #
  # Note that if you change these, you will need to update the answer_field partial.
  # app/views/admin/shared/_answer_fields.erb
  # You may also need to change the questionnaire show page.
  ##
  def self.response_types
    ['Short Text', 'Long Text', 'Number', 'Yes/No', 'File']
  end
end
