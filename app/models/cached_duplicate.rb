# Stores cached results from background duplicate detection job.
# Prevents resource-intensive fuzzy-both-names checking on every page load.
# == Schema Information
#
# Table name: cached_duplicates
# Database name: primary
#
#  id          :bigint           not null, primary key
#  bucket_type :string(255)      not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user1_id    :integer          not null
#  user2_id    :integer          not null
#
# Indexes
#
#  fk_rails_eb3a6cb896                               (user2_id)
#  index_cached_duplicates_on_bucket_type            (bucket_type)
#  index_cached_duplicates_on_user1_id_and_user2_id  (user1_id,user2_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user1_id => users.id)
#  fk_rails_...  (user2_id => users.id)
#
class CachedDuplicate < ApplicationRecord
  # Length validations enforcing database column limits
  validates :bucket_type, length: { maximum: 255 }
  belongs_to :user1, class_name: "User"
  belongs_to :user2, class_name: "User"

  validates :bucket_type, inclusion: { in: %w[overlapping no_overlap] }
  validates :user1_id, uniqueness: { scope: :user2_id }

  scope :overlapping, -> { where(bucket_type: "overlapping") }
  scope :no_overlap, -> { where(bucket_type: "no_overlap") }

  # Ensure user1_id < user2_id for consistent ordering and uniqueness
  before_validation :order_user_ids

  private

  def order_user_ids
    if user2_id && user1_id && user2_id < user1_id
      self.user1_id, self.user2_id = user2_id, user1_id
    end
  end
end
