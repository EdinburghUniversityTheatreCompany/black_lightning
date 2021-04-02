class AddMembersOnlyTextToEvent < ActiveRecord::Migration[6.0]
  def change
    add_column :events, :members_only_text, :text

    editable_block = Admin::EditableBlock.find_by(name: 'Event Members-Only Text Default')
    default_text = editable_block.content

    Event.all.each do |event|
      event.update(members_only_text: default_text)
    end
  end
end
