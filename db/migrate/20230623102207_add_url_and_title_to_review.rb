class AddUrlAndTitleToReview < ActiveRecord::Migration[7.0]
  def up
    add_column :reviews, :title, :string
    add_column :reviews, :url, :string
    rename_column :reviews, :show_id, :event_id

    Review.all.each do |review|
      event_name = review.event&.name || 'Unknown Event'
      review.update(title: "Review for #{event_name}")
    end
  end

  def down
    rename_column :reviews, :event_id, :show_id
    remove_column :reviews, :url, :string
    remove_column :reviews, :title, :string
  end
end
