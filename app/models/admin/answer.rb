##
# Represents an answer to an Admin::Question.
#
# May have an attached file if the response_type requires it.
#
# == Schema Information
#
# Table name: admin_answers
# Database name: primary
#
#  id                :integer          not null, primary key
#  answer            :text(16777215)
#  answerable_type   :string(255)
#  file_content_type :string(255)
#  file_file_name    :string(255)
#  file_file_size    :integer
#  file_updated_at   :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  answerable_id     :integer
#  question_id       :integer
#
# Indexes
#
#  index_admin_answers_on_answerable_type                    (answerable_type)
#  index_admin_answers_on_answerable_type_and_answerable_id  (answerable_type,answerable_id)
#  index_admin_proposals_answers_on_question_id              (question_id)
#
class Admin::Answer < ApplicationRecord
  # Length validations enforcing database column limits
  validates :answer, length: { maximum: 16777215 }
  validates :answerable_type, length: { maximum: 255 }
  validates :file_file_name, length: { maximum: 255 }
  validates :file_content_type, length: { maximum: 255 }
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
