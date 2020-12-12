class CreateEventTags < ActiveRecord::Migration[6.0]
  def change
    create_table :event_tags do |t|
      t.string :name
      t.text :description
      
      t.timestamps
    end

    create_join_table :events, :event_tags
  end
end
