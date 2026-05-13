class AddPolymorphicCompositeIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_answers, [ :answerable_type, :answerable_id ]
    add_index :admin_questions, [ :questionable_type, :questionable_id ]
    add_index :pictures, [ :gallery_type, :gallery_id ]
  end
end
