class CreateReimbursementsOwnerEndorsements < ActiveRecord::Migration[8.1]
  def change
    # A budget owner's sign-off that an expense charged to their budget is
    # legitimate — a blocking gate the finance team can't approve past until it
    # exists (or is overridden). Any one owner suffices; a submitter who owns
    # the budget is auto-bypassed and needs no row here. Airtable's schema isn't
    # ours to change, so this lives in MySQL (and survives the planned cutover),
    # keyed by the Airtable expense/budget record ids.
    create_table :reimbursements_owner_endorsements do |t|
      t.string :expense_record_id, null: false
      t.string :budget_record_id, null: false
      # The owner's People record id when an owner endorsed; null for a finance
      # override (owners couldn't act — e.g. none has a portal account).
      t.string :endorsed_by_person_id
      # Set when the finance team overrode the gate rather than an owner acting.
      # users is a legacy integer-PK table, so the FK column must be :integer.
      t.references :overridden_by, type: :integer, foreign_key: { to_table: :users }
      t.string :note
      t.datetime :endorsed_at, null: false
      t.timestamps
    end

    # One satisfaction per expense (any one owner suffices).
    add_index :reimbursements_owner_endorsements, :expense_record_id, unique: true
  end
end
