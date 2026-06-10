class AddInstagramToCompanies < ActiveRecord::Migration[8.1]
  def change
    add_column :companies, :instagram, :string
  end
end
