class AddNightlyConfigToReimbursementsCostCentres < ActiveRecord::Migration[8.1]
  # Per-cost-centre nightly auto-submit config + the EUSA signature name, edited
  # in the Settings screen (Phase F). Ports bedlam-bacs' per-user config.toml
  # (nightly_run_days) and the systemd nightly's last-run marker (nightly_state.toml)
  # onto the cost centre row.
  #
  # * eusa_signature_name — the name signing the EUSA request email.
  # * nightly_run_days     — JSON array of Ruby wday numbers (0=Sun..6=Sat) the
  #                          nightly job runs on. Default [2, 4] = Tue/Thu. A
  #                          string column (not text) so MySQL can hold a default;
  #                          a weekday array is a handful of bytes.
  # * last_nightly_run_on  — the date the nightly last completed, so a run-day
  #                          fires at most once (replaces nightly_state.toml).
  #
  # All strong_migrations-safe: nullable/defaulted columns on a tiny table.
  def change
    add_column :reimbursements_cost_centres, :eusa_signature_name, :string
    add_column :reimbursements_cost_centres, :nightly_run_days, :string, default: "[2,4]", null: false
    add_column :reimbursements_cost_centres, :last_nightly_run_on, :date
  end
end
