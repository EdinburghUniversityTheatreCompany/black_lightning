class CreateAdminDebtNotifications < ActiveRecord::Migration
  def change
    create_table :admin_debt_notifications do |t|
      t.references :user, index: true, foreign_key: true
      t.date :sent_on

      t.timestamps null: false
    end
  end
end
