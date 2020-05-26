class Opportunity < ApplicationRecord
  belongs_to :creator,  class_name: User
  belongs_to :approver, class_name: User

  validates :title, :expiry_date, :description, :creator_id, presence: true

  # If you update this, you must also update the active? method and the permission somewhere at the top of ability.rb.
  # You might also have to update the opportunities helper.
  scope :active, -> { where('approved = true AND expiry_date > ?', Time.now).order('expiry_date ASC') }

  def active?
    return approved && expiry_date > Time.now
  end

  def css_class
    return '' unless expiry_date > Time.now

    if active?
      return 'class="success"'.html_safe
    else
      return 'class="error"'.html_safe
    end
  end
end
