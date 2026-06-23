##
# Represents questions in the <tt>questionnable</tt> polymorphic association.
#
# Questions have Answers you know.
#
# == Schema Information
#
# Table name: admin_questions
# Database name: primary
#
#  id                :integer          not null, primary key
#  question_text     :text(16777215)
#  questionable_type :string(255)
#  response_type     :string(255)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  questionable_id   :integer
#
# Indexes
#
#  index_admin_questions_on_questionable_id                        (questionable_id)
#  index_admin_questions_on_questionable_type                      (questionable_type)
#  index_admin_questions_on_questionable_type_and_questionable_id  (questionable_type,questionable_id)
#
class Admin::Question < ApplicationRecord
  validates :question_text, :response_type, presence: true

  belongs_to :questionable, polymorphic: true

  has_many :answers, class_name: "Admin::Answer", dependent: :destroy

  ##
  # Defines the possible response types.
  #
  # Note that if you change these, you will need to update the answer_field partial.
  # app/views/admin/shared/_answer_fields.erb
  # You may also need to change the questionnaire show page.
  ##
  def self.response_types
    [ "Short Text", "Long Text", "Number", "Yes/No", "File" ]
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[question_text response_type]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[questionable]
  end
end
