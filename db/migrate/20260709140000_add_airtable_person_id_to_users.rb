class AddAirtablePersonIdToUsers < ActiveRecord::Migration[8.1]
  def change
    # Cached link to the reimbursements Airtable People record (payee registry).
    add_column :users, :airtable_person_id, :string
  end
end
