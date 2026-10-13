class AddSuggestedDepartmentToOpportunityRoles < ActiveRecord::Migration[8.1]
  def change
    add_column :opportunity_roles, :suggested_department, :string
  end
end
