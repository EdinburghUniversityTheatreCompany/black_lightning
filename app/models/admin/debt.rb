class Admin::Debt
  DISABLED_PERMISSIONS = %w[create update delete manage].freeze

  def initialize(id)
    @id = id
  end

  def id
    @id
  end

  def self.users_oldest_debt(user_id)
    user = User.find(user_id)
    oldest_maintenance_debt_date = user.admin_maintenance_debts.unfulfilled.minimum(:due_by)
    oldest_staffing_debt_date = user.admin_staffing_debts.unfulfilled.minimum(:due_by)
    out = [ oldest_maintenance_debt_date, oldest_staffing_debt_date ].compact.min
    out
  end
end
