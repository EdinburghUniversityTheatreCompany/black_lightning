class AddPublicDetailsToUser < ActiveRecord::Migration
  def change
    add_column :users, :public_profile, :boolean
    add_column :users, :bio,            :text
    add_attachment :users, :avatar
  end
end
