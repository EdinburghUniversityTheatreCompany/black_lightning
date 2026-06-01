class Admin::Debt
  DISABLED_PERMISSIONS = %w[create update delete manage].freeze

  def initialize(id)
    @id = id
  end

  def id
    @id
  end

  def self.users_oldest_debt(user_id)
    user = user_id.is_a?(User) ? user_id : User.find(user_id)
    oldest_maintenance_debt_date = user.admin_maintenance_debts.unfulfilled.minimum(:due_by)
    oldest_staffing_debt_date = user.admin_staffing_debts.unfulfilled.minimum(:due_by)
    [ oldest_maintenance_debt_date, oldest_staffing_debt_date ].compact.min
  end

  def self.oldest_debt_dates_for_users(users)
    user_ids = users.map(&:id)
    maint = Admin::MaintenanceDebt.unfulfilled.where(user_id: user_ids).group(:user_id).minimum(:due_by)
    staff = Admin::StaffingDebt.unfulfilled.where(user_id: user_ids).group(:user_id).minimum(:due_by)
    user_ids.index_with { |uid| [ maint[uid], staff[uid] ].compact.min }
  end
end
