class CreateMarketingCreativesCategoryInfos < ActiveRecord::Migration[6.0]
  def change
    create_table :marketing_creatives_category_infos do |t|
      t.references :profile, null: true, type: :bigint, foreign_key: { to_table: :marketing_creatives_profiles }
      t.references :category, null: true, type: :bigint, foreign_key: { to_table: :marketing_creatives_categories }

      t.text :description
      # Image + pictures don't need to be included in the migration.

      t.timestamps
    end
  end
end
