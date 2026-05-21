class FinaliseOpportunitiesEmailVisibility < ActiveRecord::Migration[8.1]
  def up
    change_column_null :opportunities, :email_visibility, false
    change_column_default :opportunities, :email_visibility, 0
    remove_column :opportunities, :show_email
  end

  def down
    add_column :opportunities, :show_email, :boolean, default: false
    execute "UPDATE opportunities SET show_email = CASE WHEN email_visibility = 2 THEN 1 ELSE 0 END"
    change_column_null :opportunities, :email_visibility, true
    change_column_default :opportunities, :email_visibility, nil
  end
end
