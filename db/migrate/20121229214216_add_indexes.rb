class AddIndexes < ActiveRecord::Migration
  def change
    add_index :admin_answers,       :answerable_type

    add_index :admin_questions,     :questionable_id
    add_index :admin_questions,     :questionable_type

    add_index :admin_staffing_jobs, :staffable_type

    add_index :children_techies,    :techie_id

    add_index :events,              :venue_id
    add_index :events,              :season_id

    add_index :news,                :author_id

    add_index :permissions_roles,   :role_id

    add_index :pictures,            :gallery_id
    add_index :pictures,            :gallery_type
  end
end
