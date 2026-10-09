class StripAreaPrefixFromBudgetNames < ActiveRecord::Migration[8.1]
  def up
    # Ran in production on 2026-09-11. Its code was deleted afterwards.
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "the 2026-09-11 area prefix rename cannot be undone: its code was deleted"
  end
end
