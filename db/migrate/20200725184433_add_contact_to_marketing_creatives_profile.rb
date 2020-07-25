class AddContactToMarketingCreativesProfile < ActiveRecord::Migration[6.0]
  def change
    add_column :marketing_creatives_profiles, :contact, :text
  end
end
