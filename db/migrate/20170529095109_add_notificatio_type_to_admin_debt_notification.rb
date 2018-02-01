class AddNotificatioTypeToAdminDebtNotification < ActiveRecord::Migration
  def change
    add_column :admin_debt_notifications, :notification_type, :integer
  end
end
