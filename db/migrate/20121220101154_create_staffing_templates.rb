class CreateStaffingTemplates < ActiveRecord::Migration
  def change
    create_table :admin_staffing_templates do |t|
      t.string     :name
      t.timestamps
    end
  end
end
