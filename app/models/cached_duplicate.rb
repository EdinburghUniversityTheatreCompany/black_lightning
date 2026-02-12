# Stores cached results from background duplicate detection job.
# Prevents resource-intensive fuzzy-both-names checking on every page load.
class CachedDuplicate < ApplicationRecord
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
