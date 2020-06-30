class CreateMarketingCreativesProfiles < ActiveRecord::Migration[6.0]
  def change
    create_table :marketing_creatives_profiles do |t|
      t.string :name
      t.string :url
      t.text :about
      t.boolean :approved

      t.references :user, foreign_key: true, type: :integer

      t.index :url
      
      t.timestamps
    end
  end
end
