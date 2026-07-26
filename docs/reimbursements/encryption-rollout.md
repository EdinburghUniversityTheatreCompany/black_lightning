# Reimbursements bank-details encryption — production rollout runbook

Companion to [mysql-cutover-runbook.md](mysql-cutover-runbook.md). Track F encrypts the
payee bank details at rest with **ActiveRecord Encryption** (non-deterministic), so a
database dump, backup, or replica no longer exposes UK sort codes / account numbers in
cleartext.

## What ships in the code

- `encrypts :sort_code, :account_number, :notes` on `Reimbursements::PaymentDetails`.
- `encrypts :sort_code_override, :account_number_override, :payee_name_override` on
  `Reimbursements::Expense`.
- `config.active_record.encryption.support_unencrypted_data = true` (all envs, in
  `config/application.rb`) — during the rollout this lets the app **read** rows that are
  still plaintext, so nothing breaks between deploy and backfill.
- `lib/tasks/reimbursements_encrypt_backfill.rake` — re-saves every payee record so its
  bank details land as ciphertext (`bin/rails reimbursements:encrypt_backfill`).
- `config.active_record.encryption.validate_column_size = false` — Rails' auto-injected
  guard validates the **decrypted** value against the column limit, which is the wrong
  value (the ciphertext is what has to fit), and it broke `database_consistency` on both
  encrypted models. Explicit plaintext length validations on the models take its place.
- **One schema migration IS needed**, contrary to what this doc originally claimed:
  `20260725150000_widen_reimbursements_payee_name_override_for_encryption` changes
  `reimbursements_expenses.payee_name_override` from `string(255)` to `text`. AR Encryption
  stores a JSON envelope of base64 IV + ciphertext + auth tag, so a low-redundancy plaintext
  of ~124 characters already exceeds 255 bytes and 255 characters lands at ~394 — the pre-
  encryption column could no longer hold every value it used to. The other encrypted columns
  were measured and genuinely do fit: `sort_code`, `account_number`,
  `sort_code_override` and `account_number_override` are format-validated to 6 and 8 digits
  (~82 bytes encrypted, in `string(255)`), and `notes` is already `text` and compresses.
  `test/models/reimbursements/encryption_test.rb` pins all three measurements.

## Where the keys live, per environment

| Env | Source | Notes |
|---|---|---|
| production | `config/credentials/production.yml.enc` under `active_record_encryption:` | Rails' `active_record` railtie reads these automatically. |
| development | `REIMBURSEMENTS_AR_ENCRYPTION_PRIMARY_KEY` / `_DETERMINISTIC_KEY` / `_KEY_DERIVATION_SALT` from ENV (fnox), else the throwaway literals in `config/application.rb` | `config/credentials/development.key` is **committed**, so `development.yml.enc` protects nothing — key material must never go there. The literals exist because an encrypted attribute needs a key on write even when blank: without them every `Expense.create!` in a fnox-less dev shell raised "Missing Active Record encryption credential". |
| test | literal dummy keys in `config/environments/test.rb` | Throwaway, test-only, safe to commit. |

## Rollout sequence (production)

**Steps 1 and 2 are already done** (commit `0b606bb7`): a fresh key set was minted and added
to `config/credentials/production.yml.enc`. Start at step 3. The two steps are kept below for
the record and for any future key rotation.

1. ~~**Mint the production key set**~~ (done). To rotate, locally run:

   ```
   bin/rails db:encryption:init
   ```

   It prints a block like:

   ```
   active_record_encryption:
     primary_key: <PLACEHOLDER — 32-char value from db:encryption:init>
     deterministic_key: <PLACEHOLDER — 32-char value from db:encryption:init>
     key_derivation_salt: <PLACEHOLDER — 32-char value from db:encryption:init>
   ```

   > These are **new, real secrets** — do **not** reuse the throwaway keys from the test
   > env, and do not commit them anywhere except the encrypted production credentials.

2. ~~**Add the keys to production credentials**~~ (done). To rotate, edit the encrypted file
   and replace the block at the top level (sibling to the other production keys):

   ```
   EDITOR="code --wait" bin/rails credentials:edit --environment production
   ```

   Add:

   ```yaml
   active_record_encryption:
     primary_key: <paste primary_key>
     deterministic_key: <paste deterministic_key>
     key_derivation_salt: <paste key_derivation_salt>
   ```

   Save; commit the re-encrypted `config/credentials/production.yml.enc` (never the
   `.key`).

3. **Deploy and migrate**, with `support_unencrypted_data = true` (already set in the
   code). The deploy must include
   `20260725150000_widen_reimbursements_payee_name_override_for_encryption` — the
   backfill in step 4 writes through `update_columns`, which skips validations, so the
   column has to be wide enough for the ciphertext first. At this point new writes
   encrypt; existing rows stay plaintext and read fine. **This is where the rollout
   currently stands: the keys are shipped but no data is encrypted yet.**

4. **Run the backfill** in the deployed image (kamal needs an interactive terminal on this
   host — SSH password auth):

   ```
   kamal app exec -i --reuse "bin/rails reimbursements:encrypt_backfill"
   ```

   It prints per-model processed counts. **Safe to re-run, but not a no-op:**
   `#encrypt` rewrites every row unconditionally (`update_columns`, no dirty check)
   and the encryption is non-deterministic, so each run mints a fresh IV and fresh
   ciphertext for every row, already-encrypted ones included. The end state is
   correct either way, but "processed N/N" counts rows *touched*, not rows newly
   encrypted — it is not a progress figure for a resumed partial run.

   `update_columns` also skips validations, so **the migration in step 3 must
   already be applied**: without the widened `payee_name_override` column, a long
   plaintext payee name would be truncated here.

5. **Verify** in `kamal console` that a sample row's **raw** column is ciphertext while the
   model still reads plaintext:

   ```ruby
   pd = Reimbursements::PaymentDetails.where.not(account_number: "").first
   pd.account_number                       # => plaintext, e.g. "66374958"
   ActiveRecord::Base.connection.select_value(
     "SELECT account_number FROM reimbursements_payment_details WHERE id = #{pd.id}"
   )                                        # => ciphertext blob, NOT "66374958"
   ```

   Repeat for `Reimbursements::Expense` (`account_number_override`).

6. ~~**Flip `support_unencrypted_data` off**~~ — **done 2026-07-26.**
   `config/application.rb` now sets it to `false`, so any lingering plaintext row raises on
   read instead of being served. The cleartext-at-rest risk is closed.

## Status: complete (2026-07-26)

The rollout ran on production in this order: deploy → `reimbursements:encrypt_backfill`
(10 `PaymentDetails` + 38 `Expense` records, 0 failures) → verification → flag off.
Verification swept **every** value in all six encrypted columns, not a sample, and reported
`still plaintext: 0`:

```ruby
pairs = [[Reimbursements::PaymentDetails, :account_number], [Reimbursements::PaymentDetails, :sort_code],
         [Reimbursements::PaymentDetails, :notes], [Reimbursements::Expense, :account_number_override],
         [Reimbursements::Expense, :sort_code_override], [Reimbursements::Expense, :payee_name_override]]
total = 0; plain = 0
pairs.each { |m, c| m.find_each { |r| next if r.public_send(c).blank?; total += 1; plain += 1 unless r.ciphertext_for(c).to_s.start_with?("{") } }
puts "checked #{total} values, still plaintext: #{plain}"
```

Prefer that sweep over the single-row spot check in step 5: one missed row is exactly what
raises forever once the flag is off, and a spot check cannot see it.

**Encrypting a NEW column later** means repeating the whole sequence, because
`reimbursements:encrypt_backfill` **cannot run while the flag is false** — it has to read the
plaintext to rewrite it. So: add `encrypts`, set `support_unencrypted_data = true`, deploy,
backfill, verify, set it back to `false`, deploy. The task now **refuses to start** while the
flag is false and says which flag to change, rather than reporting one decryption failure per
row and leaving you to work out why. The tests in
`test/models/reimbursements/encryption_test.rb` enable the flag for their own duration via
`with_unencrypted_data_support`, so they keep proving that mechanism works even though it is
no longer the global default.

## Rollback

**There is no rollback now.** Removing the `encrypts` declarations would leave every stored
value unreadable, and with the backfill complete there is no plaintext left to fall back to.
The production credential keys under `active_record_encryption:` are the only thing that can
read this data: lose them and the payee bank details are gone for good. Treat them with the
same care as `master.key` — and note they are *not* in the repo, so a machine that can decrypt
`production.yml.enc` is the only place they exist.
