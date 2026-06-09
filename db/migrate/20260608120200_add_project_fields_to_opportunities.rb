class AddProjectFieldsToOpportunities < ActiveRecord::Migration[8.1]
  def change
    add_reference :opportunities, :company, foreign_key: true, null: true
    add_column :opportunities, :project, :string
    add_column :opportunities, :author, :string
    add_column :opportunities, :apply_url, :string
    add_column :opportunities, :submitter_name, :string
    add_column :opportunities, :submitter_email, :string
    add_column :opportunities, :compensation_type, :integer, null: false, default: 4
    add_column :opportunities, :experience_level, :integer, null: false, default: 0

    # Existing rows all have a title; it only becomes optional for new company/project-based postings.
    change_column_null :opportunities, :title, true
  end
end
