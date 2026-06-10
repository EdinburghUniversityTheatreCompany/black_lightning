class AddDatesAndLocationToOpportunities < ActiveRecord::Migration[8.1]
  def change
    add_column :opportunities, :dates, :string
    add_column :opportunities, :location, :string
  end
end
