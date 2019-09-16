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
# *question_text*::     <tt>text</tt>
# *response_type*::     <tt>string(255)</tt>
# *created_at*::        <tt>datetime, not null</tt>
# *updated_at*::        <tt>datetime, not null</tt>
# *questionable_id*::   <tt>integer</tt>
# *questionable_type*:: <tt>string(255)</tt>
#--
# == Schema Information End
#++
##
class Admin::Question < ActiveRecord::Base
  belongs_to :questionable, polymorphic: true

  has_many :answers, class_name: 'Admin::Answer', dependent: :destroy

  validates :question_text, presence: true

  ##
  # Defines the possible response types.
  #
  # Note that if you change these, you will need to update the answer_field partial.
  # app/views/admin/shared/_answer_field.html.erb
  ##
  def self.response_types
    ['Short Text', 'Long Text', 'Number', 'Yes/No', 'File']
  end
end
