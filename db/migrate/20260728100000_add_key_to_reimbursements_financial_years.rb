class AddKeyToReimbursementsFinancialYears < ActiveRecord::Migration[8.1]
  # A financial year becomes addressable in the UI (a year selector, a year's
  # budget import), so it needs a readable URL slug the way CostCentre#key
  # already gives cost centres one — "?year=fringe-2027" rather than
  # "?year=4". The model derives it from the label when left blank.
  #
  # Nullable here and NOT NULL in the follow-up migration, per the multi-step
  # convention for a table that already has rows.
  def up
    add_column :reimbursements_financial_years, :key, :string
    add_index :reimbursements_financial_years, :key, unique: true

    # Parameterizing the label is exactly what the model's before_validation
    # does, so an existing year ends up with the key it would have been given
    # had it been created after this migration. Done row by row in Ruby because
    # MySQL has no parameterize; the table holds one row per financial year, so
    # a loop costs nothing.
    #
    # A collision can only happen if two labels differ solely by punctuation
    # ("Fringe 2026" / "Fringe, 2026"). Falling back to the id keeps the unique
    # index satisfiable rather than aborting the deploy over a cosmetic clash.
    taken = []
    select_all("SELECT id, label FROM reimbursements_financial_years").each do |row|
      key = row["label"].to_s.parameterize.presence || "year-#{row['id']}"
      key = "#{key}-#{row['id']}" if taken.include?(key)
      taken << key
      update("UPDATE reimbursements_financial_years SET #{quote_column_name('key')} = #{quote(key)} " \
             "WHERE id = #{row['id'].to_i}")
    end
  end

  def down
    remove_index :reimbursements_financial_years, :key
    remove_column :reimbursements_financial_years, :key
  end
end
