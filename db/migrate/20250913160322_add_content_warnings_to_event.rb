class AddContentWarningsToEvent < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :content_warnings, :text
  end
end
