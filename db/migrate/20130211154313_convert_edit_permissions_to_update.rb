class ConvertEditPermissionsToUpdate < ActiveRecord::Migration
  # Faux model for the migration.
  class Admin::Permission < ActiveRecord::Base
  end

  def up
    Admin::Permission.reset_column_information
    Admin::Permission.where(action: "edit").each do |product|
      product.update!(action: "update")
    end
  end

  def down
    Admin::Permission.reset_column_information
    Admin::Permission.where(action: "update").each do |product|
      product.update!(action: "edit")
    end
  end
end
