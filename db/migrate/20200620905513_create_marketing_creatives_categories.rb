class CreateMarketingCreativesCategories < ActiveRecord::Migration[6.0]
  def change
    create_table :marketing_creatives_categories do |t|
      t.string :name
      t.string :name_on_profile

      t.string :url

      # Image doesn't need to be included in the migration.

      t.index :url

      t.timestamps
    end
  end
end
