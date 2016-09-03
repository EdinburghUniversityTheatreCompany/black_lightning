class CreateFaultReports < ActiveRecord::Migration
  def change
    create_table :fault_reports do |t|
      t.string :item
      t.text :description
      t.integer :severity, index: true, default: 0
      t.integer :status, index: true, default: 0
      t.references :reported_by, index: true
      t.references :fixed_by, index: true

      t.timestamps null: false
    end
  end
end
