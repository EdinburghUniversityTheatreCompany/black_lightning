class AddIndexToNewsShowPublicPublishDate < ActiveRecord::Migration[8.0]
  def change
    add_index :news, [ :show_public, :publish_date ]
  end
end
