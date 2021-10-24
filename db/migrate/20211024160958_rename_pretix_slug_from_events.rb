class RenamePretixSlugFromEvents < ActiveRecord::Migration[6.1]
  def change
    change_table :events do |t|
      t.rename :pretix_slug, :pretix_slug_override
    end
  end
end
