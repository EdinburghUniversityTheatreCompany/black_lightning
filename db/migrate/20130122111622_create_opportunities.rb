class CreateOpportunities < ActiveRecord::Migration
  def change
    create_table :opportunities do |t|
      t.string :title
      t.text :description
      t.boolean :show_email
      t.boolean :approved
      t.integer :creator_id
      t.integer :approver_id
      t.date    :expiry_date

      t.timestamps
    end
  end
end
