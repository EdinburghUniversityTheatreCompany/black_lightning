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
  validates :slug, uniqueness: true

  has_many :reviews, dependent: :destroy
  has_many :feedbacks, class_name: 'Admin::Feedback', dependent: :destroy
  has_many :questionnaires, class_name: 'Admin::Questionnaires::Questionnaire', dependent: :destroy

  accepts_nested_attributes_for :reviews, reject_if: :all_blank, allow_destroy: true

  def create_maintenance_debts
    users.distinct.each do |user|
      next if user.admin_maintenance_debts.where(show_id: id).any?

      Admin::MaintenanceDebt.create!(
        show: self,
        user: user,
        due_by: maintenance_debt_start,
        state: :uncompleted
      )
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
