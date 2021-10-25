class AddPretixValuestoEventModel < ActiveRecord::Migration[6.1]
  def change
    add_column :events, :pretix_shown, :boolean
    add_column :events, :pretix_slug, :string
    add_column :events, :pretix_view, :string
  end
end
