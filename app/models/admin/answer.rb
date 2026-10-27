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
#  id              :integer          not null, primary key
#  answer          :text(16777215)
#  answerable_type :string(255)
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  answerable_id   :integer
#  question_id     :integer
#
# Indexes
#
#  index_admin_answers_on_answerable_type                    (answerable_type)
#  index_admin_answers_on_answerable_type_and_answerable_id  (answerable_type,answerable_id)
#  index_admin_proposals_answers_on_question_id              (question_id)
#
class Admin::Answer < ApplicationRecord
  # Paperclip's metadata, unused since the files moved to ActiveStorage. A later deploy drops them.
  self.ignored_columns += %w[file_content_type file_file_name file_file_size file_updated_at]

  validates :answer, length: { maximum: 16777215 }
  validates :answerable_type, length: { maximum: 255 }
  validates :question_id, presence: true

  belongs_to :question, class_name: "Admin::Question"
  belongs_to :answerable, polymorphic: true

  # To hold files, if necessary.
  include AttachmentItem

  default_scope { includes(:question, :attachments) }

  def self.ransackable_attributes(auth_object = nil)
    []
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end
