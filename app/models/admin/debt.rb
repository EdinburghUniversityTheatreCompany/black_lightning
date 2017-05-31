class Admin::Debt

  def initialize(id)
    @id = id
  end

  def id
    return @id
  end

  def self.users_oldest_debt(user_id)
    user = User.find(user_id)
    oldest_mdebt_date = user.admin_maintenance_debts.minimum(:due_by)
    oldest_sdebt_date = user.admin_staffing_debts.unfulfilled.minimum(:due_by)
    out = [oldest_mdebt_date,oldest_sdebt_date].compact.min
    return out
  end


end