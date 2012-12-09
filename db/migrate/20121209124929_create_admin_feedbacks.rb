class CreateAdminFeedbacks < ActiveRecord::Migration
  def change
    create_table :admin_feedbacks do |t|
      t.integer :show_id
      t.text :body

      t.timestamps
    end
  end
end
