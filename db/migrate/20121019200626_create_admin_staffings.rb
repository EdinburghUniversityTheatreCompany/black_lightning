class CreateAdminStaffings < ActiveRecord::Migration
  def change
    create_table :admin_staffings do |t|
      t.datetime   :date
      t.string     :show_title
      t.timestamps
    end
  end
end
