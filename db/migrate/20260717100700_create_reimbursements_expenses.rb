class CreateReimbursementsExpenses < ActiveRecord::Migration[8.1]
  # Expense submissions mirroring the Airtable Expenses table (Phase H cutover).
  # This is the hot table: the Store lists it on every operator/portal request,
  # so the lookup columns are indexed.
  #
  # person/budget/batch FKs are nullable because email-in submissions arrive
  # with gaps the submitter fills in later. Receipts become ActiveStorage
  # (has_many_attached :receipt_files) — no column here.
  #
  # status stays a plain string so Phase E's "Budget approved" value needs no
  # schema change — only a new Status constant.
  #
  # source_message_id is the mailbox idempotency key the Airtable era couldn't
  # have (deferred-robustness item): the poll job stamps the Graph message id
  # on the expense it creates and skips a message it has already seen, closing
  # the duplicate-on-failed-move window for good. Unique; NULL for portal
  # submissions (MySQL unique indexes allow multiple NULLs).
  def change
    create_table :reimbursements_expenses do |t|
      # Airtable auto-number, kept for the human-facing "Expense #N" label;
      # the model continues the sequence for new rows.
      t.integer :auto_number

      t.references :person, type: :bigint, null: true,
                            foreign_key: { to_table: :reimbursements_people }, index: true
      t.references :budget, type: :bigint, null: true,
                            foreign_key: { to_table: :reimbursements_budgets }, index: true
      t.references :batch, type: :bigint, null: true,
                           foreign_key: { to_table: :reimbursements_batches }, index: true
      t.references :financial_year, type: :bigint, null: true,
                                    foreign_key: { to_table: :reimbursements_financial_years }, index: true

      t.decimal :amount, precision: 12, scale: 2
      t.decimal :amount_excl_vat, precision: 12, scale: 2
      t.text :description
      t.string :status, null: false, default: "Pending"
      # Single-select in Airtable (Reimbursement / Invoice / From EUSA).
      t.string :expense_type, null: false, default: "Reimbursement"

      # Invoice payee overrides: pay a third party directly (the money path
      # uses effective_* which prefer these over the linked person's details).
      t.string :payee_name_override
      t.string :sort_code_override
      t.string :account_number_override
      t.string :nominal_code_override

      t.string :payment_reference
      t.text :rejection_reason
      t.datetime :rejection_notified

      # Airtable's created-time; an explicit column so ordering/display
      # survive the import independently of this row's own created_at.
      t.datetime :submitted_at
      t.date :submitted_to_eusa_date
      t.date :payment_confirmed_date

      t.boolean :producer_notified, null: false, default: false
      t.boolean :receipts_offloaded, null: false, default: false
      # One SharePoint URL per line (mirrors the Airtable multiline field).
      t.text :sharepoint_receipt_urls

      t.string :ai_check_status, null: false, default: ""
      t.text :ai_comment
      t.datetime :ai_checked_at

      t.string :source_message_id
      t.string :airtable_record_id

      t.timestamps
    end

    # Review/Build Batch/History partition by status; the poll job de-dupes by
    # source_message_id; import + endorsement remap join on airtable_record_id.
    add_index :reimbursements_expenses, :status
    add_index :reimbursements_expenses, :auto_number
    add_index :reimbursements_expenses, :source_message_id, unique: true
    add_index :reimbursements_expenses, :airtable_record_id, unique: true
  end
end
