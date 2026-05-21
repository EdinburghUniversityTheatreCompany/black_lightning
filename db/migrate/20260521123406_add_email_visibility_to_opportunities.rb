class AddEmailVisibilityToOpportunities < ActiveRecord::Migration[8.1]
  def up
    add_column :opportunities, :email_visibility, :integer
    add_column :opportunities, :contact_email, :string

    # Migrate: show_email=true → everyone(2), show_email=false → no_one(0)
    execute "UPDATE opportunities SET email_visibility = CASE WHEN show_email = 1 THEN 2 ELSE 0 END"
  end

  def down
    remove_column :opportunities, :email_visibility
    remove_column :opportunities, :contact_email
  end
end
