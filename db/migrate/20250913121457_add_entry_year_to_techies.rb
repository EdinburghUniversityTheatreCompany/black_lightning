class AddEntryYearToTechies < ActiveRecord::Migration[8.0]
  def change
    add_column :techies, :entry_year, :integer
  end
end
