class AddCompanyToEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :events, :company, null: true, foreign_key: true
  end
end
