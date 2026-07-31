class RemoveAiColumnsFromReimbursementsExpenses < ActiveRecord::Migration[8.1]
  # The Gemini receipt extractor and the finance AI checker were removed
  # entirely, so nothing reads or writes these any more. Dropping them rather
  # than leaving them behind: unlike the airtable_record_id columns (kept as
  # import provenance for rows we still hold), a stale AI verdict describes a
  # check no code can re-run or explain, and the consent flag answers a question
  # the form no longer asks.
  #
  # safety_assured: every reference is removed in this same change, so
  # strong_migrations' ignored_columns dance (deploy the ignore, then deploy the
  # drop) buys nothing here — there is no later deploy that still reads them.
  #
  # Explicit up/down rather than `change`, matching
  # 20260707120000_drop_orphan_google_columns_from_users: the column_exists?
  # guards make a re-run a no-op, and an auto-reversed `change` would re-evaluate
  # them against post-migration state and silently skip re-adding the columns.
  #
  # `down` restores the columns but NOT their data — the verdicts and consent
  # answers are gone for good. It exists so a rollback leaves a schema the old
  # code could load, not so the feature can come back.
  COLUMNS = {
    ai_check_status: { type: :string, options: { null: false, default: "" } },
    ai_checked_at: { type: :datetime, options: {} },
    ai_comment: { type: :text, options: {} },
    ai_processing_consent: { type: :boolean, options: {} }
  }.freeze

  def up
    safety_assured do
      COLUMNS.each_key do |name|
        remove_column :reimbursements_expenses, name if column_exists?(:reimbursements_expenses, name)
      end
    end
  end

  def down
    COLUMNS.each do |name, spec|
      next if column_exists?(:reimbursements_expenses, name)

      add_column :reimbursements_expenses, name, spec[:type], **spec[:options]
    end
  end
end
