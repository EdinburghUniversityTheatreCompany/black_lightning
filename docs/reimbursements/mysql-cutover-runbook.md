# Reimbursements MySQL cutover — production runbook

Companion to [mysql-migration-and-roadmap.md](mysql-migration-and-roadmap.md). The
`reimbursements-mysql-cutover` branch ships both backends behind one switch:
`REIMBURSEMENTS_BACKEND` (`airtable` = default today, `database` = MySQL). Flipping the
env var is the cutover; flipping it back is the rollback.

## What the branch contains

- The full `reimbursements_*` schema (people, payment_details, budgets, budget_owners,
  budget_forecasts, batches, expenses, eusa_actuals, financial_years) plus
  `users.reimbursements_person_id`. Migrations are additive and safe to deploy ahead of
  the flip — nothing reads the tables while the flag is `airtable`.
- `Reimbursements::AirtableImporter` (`bin/rails reimbursements:import_airtable`),
  idempotent and re-runnable; verifies counts + an amount/status checksum + receipt
  presence, and remaps `owner_endorsements` / `batch_attempts` /
  `users.airtable_person_id → reimbursements_person_id`.
- `Reimbursements::DatabaseStore` behind `Reimbursements.build_store`; receipts on
  ActiveStorage; mailbox idempotency via `expenses.source_message_id`.

## Cutover steps

1. **Deploy the branch with the flag off** (no `REIMBURSEMENTS_BACKEND` set → airtable).
   Migrations create the empty tables. The app behaves exactly as before.
2. **First import (rehearsal).** The rake task ships in this deploy, so run it in the
   deployed image — note kamal needs an interactive terminal on this host (SSH password
   auth): `kamal app exec -i --reuse "bin/rails reimbursements:import_airtable"`.
   Optionally `YEAR_LABEL="Fringe 2026"`. Expect `Import verified.` — it fails loudly on
   duplicate People emails (merge them in Airtable and re-run) or any count/checksum
   mismatch. Costs ~6 Airtable list calls per run.
3. **Spot-check in `kamal console`:** `Reimbursements::Expense.count`,
   `Reimbursements::Expense.joins(:receipt_files_attachments).distinct.count`,
   a couple of `Budget` rollups (`committed_amount`, `remaining`) against the Airtable
   base, and `User.where.not(reimbursements_person_id: nil).count`.
4. **Final import + flip in a quiet moment** (no batch mid-build, poll job idle):
   re-run the import (cheap, idempotent — picks up rows created since), then set
   `REIMBURSEMENTS_BACKEND=database` in the deploy env and redeploy/restart. From this
   moment writes land in MySQL only.
5. **Smoke-test the flip:**
   - portal index renders; a test expense submits and appears in
     `Reimbursements::Expense.last` with a receipt attached;
   - budgets screen shows sane figures (committed/paid/forecast/remaining);
   - send a test receipt email → poll creates a draft with `source_message_id` set;
   - Review approves it; log shows zero Airtable calls.
6. **Rollback (only before meaningful MySQL-only writes):** unset the env var and
   restart — the app reads Airtable again instantly. Any expenses/receipts created on
   MySQL during the window must then be re-entered in Airtable by hand, so keep the
   watch window short and attentive.
7. **Afterwards:** run a full cycle (submit → approve → Build Batch → reconcile) on
   MySQL. Once green, make the Airtable base read-only, then raise the cleanup PR:
   delete the Airtable client/config/mapper/POROs + PAT + `Store` (renaming
   `DatabaseStore` in), retire `users.airtable_person_id` and the
   `airtable_record_id` columns, and drop the Airtable probe from the status page.

## Notes

- `Batch#eusa_draft_created` no longer exists as data — it derives from
  `draft_message_id` / `date_sent`. Legacy sent batches read as drafted, which is
  correct for display.
- New expenses stamp `submitted_at` and continue the `auto_number` sequence
  automatically; both were Airtable auto-fields.
- The Solid Cache `reimbursements/*` keys simply expire unused after the flip.
- The reimbursements test suite runs against the database backend by default since
  this branch; Airtable-era store behaviour keeps its own injected-fake tests until
  the cleanup PR.
