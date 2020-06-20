##
# == Schema Information
#
# Table name: events
#
#  id                     :integer          not null, primary key
#  name                   :string(255)
#  tagline                :string(255)
#  slug                   :string(255)
#  description            :text(65535)
#  xts_id                 :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  is_public              :boolean
#  image_file_name        :string(255)
#  image_content_type     :string(255)
#  image_file_size        :integer
#  image_updated_at       :datetime
#  start_date             :date
#  end_date               :date
#  venue_id               :integer
#  season_id              :integer
#  author                 :string(255)
#  type                   :string(255)
#  price                  :string(255)
#  spark_seat_slug        :string(255)
#  maintenance_debt_start :date
#  staffing_debt_start    :date
#

class Show < Event
  include ApplicationHelper
  
  validates :author, :price, presence: true

  # Validate uniqueness on Event Subtype basis instead of on the event.
  # Otherwise, you cannot have two different types with the same slug.
  validates :slug, uniqueness: { case_sensitive: false }

  has_many :reviews, dependent: :restrict_with_error
  has_many :feedbacks, class_name: 'Admin::Feedback', dependent: :restrict_with_error

  accepts_nested_attributes_for :reviews, reject_if: :all_blank, allow_destroy: true

  # If you add more fields, you might need to add to this.
  # This is to prevent data loss from occuring when converting a Show into another type of event.
  # Please also modify the error messagse in admin Show controller that is displayed when this returns false
  # and the confirm message on the admin Shows show page for converting.
  def can_convert?
    return reviews.empty? && feedbacks.empty?
  end

  def create_maintenance_debts
    users.distinct.each do |user|
      debts = user.admin_maintenance_debts.where(show_id: id)

      if debts.empty?
        Admin::MaintenanceDebt.create!(
          show: self,
          user: user,
          due_by: maintenance_debt_start,
          state: :unfulfilled
        )
      else
        debts.each do |debt| 
          debt.update!(due_by: maintenance_debt_start)
        end
      end 
    end
  end

  def create_staffing_debts(total_amount)
    users.distinct.each do |user|
      amount = total_amount - user.admin_staffing_debts.where(show_id: id, converted: false).count
      amount.times do
        Admin::StaffingDebt.create!(
          show: self,
          user: user,
          due_by: staffing_debt_start,
          converted: false,
          forgiven: false
        )
      end
    end
  end

  def as_json(options = {})
    defaults = {
      include: [
          :reviews
      ]
    }

    options = merge_hash(defaults, options)

    super(options)
  end
end
