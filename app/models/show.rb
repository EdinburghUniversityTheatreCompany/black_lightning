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
  has_many :reviews, dependent: :destroy
  has_many :feedbacks, class_name: 'Admin::Feedback', dependent: :destroy
  has_many :questionnaires, class_name: 'Admin::Questionnaires::Questionnaire', dependent: :destroy

  accepts_nested_attributes_for :reviews, reject_if: :all_blank, allow_destroy: true

  def create_questionnaire(name)
    questionnaire = Admin::Questionnaires::Questionnaire.new
    questionnaire.show = self
    questionnaire.name = name
    questionnaire.save!
  end

  def create_maintenance_debts
    uniqueTeam = self.users.distinct
    uniqueTeam.each do |usr, index|
      if !usr.admin_maintenance_debts.where(show_id: self.id).any?
        debt = Admin::MaintenanceDebt.new
        debt.show = self
        debt.user = usr
        debt.due_by = self.maintenance_debt_start
        debt.state = :unfulfilled
        debt.save!
      end
    end
  end

  def create_staffing_debts(numEach)
    uniqueTeam = self.users.distinct
    uniqueTeam.each do |usr|
      x = numEach - usr.admin_staffing_debts.where(show_id:self.id, converted: false).count
      x.times do |i|
        debt = Admin::StaffingDebt.new
        debt.show = self
        debt.user = usr
        debt.due_by = self.staffing_debt_start
        debt.converted = false
        debt.forgiven = false
        debt.save!
      end
    end
  end

  def as_json(options = {})
    defaults = {
        include: [
            :reviews
        ]
    }

    options = options.merge(defaults) do |_key, oldval, newval|
      # http://stackoverflow.com/a/11171921
      (newval.is_a?(Array) ? (oldval + newval) : (oldval << newval)).distinct
    end

    super(options)
  end
end
