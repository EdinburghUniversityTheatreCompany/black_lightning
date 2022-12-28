class AddAddressToVenues < ActiveRecord::Migration[7.0]
  def change
    add_column :venues, :address, :text
  end
end
