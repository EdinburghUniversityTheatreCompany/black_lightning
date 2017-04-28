class AddHadDebtors < ActiveRecord::Migration
  def change
    add_column :admin_proposals_proposals, :had_debtors_on_creation, :boolean
  end
end
