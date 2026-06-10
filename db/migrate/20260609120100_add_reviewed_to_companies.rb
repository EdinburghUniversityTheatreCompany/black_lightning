class AddReviewedToCompanies < ActiveRecord::Migration[8.1]
  def up
    add_column :companies, :reviewed, :boolean, default: false, null: false

    # Existing companies were curated by admins, so treat them as already reviewed.
    # Companies created from free-text submissions afterwards default to false.
    Company.reset_column_information
    Company.update_all(reviewed: true)
  end

  def down
    remove_column :companies, :reviewed
  end
end
