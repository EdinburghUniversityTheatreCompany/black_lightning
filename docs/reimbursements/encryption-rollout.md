# Reimbursements bank-details encryption

Payee bank details are encrypted at rest with **Active Record Encryption** (non-deterministic), so
a database dump, backup or replica does not expose them.

## What is encrypted

| Model | Columns |
|---|---|
| `Reimbursements::PaymentDetails` | `sort_code`, `account_number`, `iban`, `bic`, `notes` |
| `Reimbursements::Expense` | `sort_code_override`, `account_number_override`, `payee_name_override`, `iban_override`, `bic_override` |

The rollout is finished. Production was backfilled on 2026-07-26 (10 `PaymentDetails` and 38
`Expense` records, 0 failures). The four IBAN/BIC columns came later and were new, so they never
held plaintext.

**The check run that day proved nothing.** It tested `ciphertext_for`, which encrypts a plaintext
value on the way out, so every value looked like ciphertext. Run the sweep below once in
production to confirm the backfill. Until then, its 0 failures is the only evidence.

`config.active_record.encryption.support_unencrypted_data` is `false` (`config/application.rb`),
so a plaintext value **raises** on read rather than being served.

## Column sizes

Rails' auto-injected `validate_column_size` guard is off
(`config.active_record.encryption.validate_column_size = false`). It measures the **decrypted**
value against the column limit, which is the wrong value, and it broke `database_consistency` on
both models. Explicit plaintext length validations on the models do that job instead.

The ciphertext is what has to fit. Active Record Encryption stores a JSON envelope of base64 IV,
ciphertext and auth tag, so a low-redundancy plaintext of about 124 characters already exceeds
255 bytes, and 255 characters lands at about 394. That is why
`20260725150000_widen_reimbursements_payee_name_override_for_encryption` made
`payee_name_override` a `text` column. The sort code and account number columns are
format-validated to 6 and 8 digits (about 82 bytes encrypted) and fit in `string(255)`; `notes`
is `text` and compresses. `test/models/reimbursements/encryption_test.rb` pins these measurements.

## Where the keys live

| Env | Source | Notes |
|---|---|---|
| production | `config/credentials/production.yml.enc` under `active_record_encryption:` | Rails' `active_record` railtie reads these automatically. |
| development | `REIMBURSEMENTS_AR_ENCRYPTION_PRIMARY_KEY` / `_DETERMINISTIC_KEY` / `_KEY_DERIVATION_SALT` from ENV if set, else the throwaway literals in `config/application.rb` | `config/credentials/development.key` is **committed**, so `development.yml.enc` protects nothing: key material must never go there. The literals exist because an encrypted attribute needs a key on write even when blank. |
| test | literal dummy keys in `config/environments/test.rb` | Throwaway, test-only, safe to commit. |

## Rotating the keys

**Append, never replace.** Rails takes `primary_key` as a list: it encrypts with the **last** key
and tries every key in the list when decrypting. Replace the key instead of adding to the list
and every stored value becomes unreadable, with no way back.

1. Run `bin/rails db:encryption:init` locally and take only the `primary_key` it prints.
2. `EDITOR="code --wait" bin/rails credentials:edit --environment production`, and add the new
   key to the end of the list:

   ```yaml
   active_record_encryption:
     primary_key:
       - <the existing key, unchanged>
       - <the new key>
     deterministic_key: <unchanged>
     key_derivation_salt: <unchanged>
   ```

   Leave `key_derivation_salt` alone: every key is derived through it, so changing it locks out
   all existing rows just as replacing the key would.
3. Commit the re-encrypted `config/credentials/production.yml.enc` (never the `.key`) and deploy.

Existing rows move to the new key only when they are next saved, so the old key stays in the list
for as long as any row was written with it.

## Encrypting a new column

**A brand-new column with no plaintext rows:** add `encrypts` and deploy. Nothing needs
backfilling. This is how the IBAN/BIC columns went in.

**A column that already holds plaintext** needs the full sequence, because
`reimbursements:encrypt_backfill` **cannot run while `support_unencrypted_data` is false**: it has
to read the plaintext to rewrite it. The task refuses to start and names the flag.

1. Add `encrypts`, set `support_unencrypted_data = true`, and widen the column if the ciphertext
   will not fit (see above). Deploy and migrate. New writes now encrypt and existing rows still
   read.
2. Run the backfill in the deployed image. Kamal needs an interactive terminal on this host (SSH
   password auth):

   ```
   kamal app exec -i --reuse "bin/rails reimbursements:encrypt_backfill"
   ```

   - **The column must already be wide enough.** The task writes with `update_columns`, which
     skips validations, so a too-narrow column truncates the value.
   - **Safe to re-run, but not a no-op.** `#encrypt` rewrites every row with no dirty check, and
     each run mints a fresh IV and ciphertext for every row, already-encrypted ones included. So
     "processed N/N" counts rows touched, not rows newly encrypted, and says nothing about
     progress across a resumed run.
   - It exits non-zero if any row failed. Fix those first: turning the flag off over an
     unconverted row makes it unreadable.
3. Run the sweep below. It must report `still plaintext: 0`.
4. Set `support_unencrypted_data = false` and deploy.

The tests in `test/models/reimbursements/encryption_test.rb` switch the flag on for their own
duration (`with_unencrypted_data_support`), so they keep proving the mechanism works.

### The all-rows sweep

Run it in `kamal console`. It reads the raw column and never decrypts, so it works with the flag
on or off. It checks every value rather than a sample, because one missed row is exactly what
raises for ever once the flag is off.

```ruby
total = 0; plain = 0
[Reimbursements::PaymentDetails, Reimbursements::Expense].each do |model|
  model.find_each do |record|
    model.encrypted_attributes.each do |column|
      next if record.read_attribute_before_type_cast(column).blank?
      total += 1
      plain += 1 unless record.encrypted_attribute?(column)
    end
  end
end
puts "checked #{total} values, still plaintext: #{plain}"
```

**Don't test `ciphertext_for(column)` instead.** On a plaintext value it returns that value
encrypted on the fly, so a plaintext row always looks like ciphertext.

## Rollback

**There is none.** Removing the `encrypts` declarations would leave every stored value unreadable,
and there is no plaintext left to fall back to. The production keys under
`active_record_encryption:` are the only thing that can read this data: lose them and the payee
bank details are gone for good. Treat them with the same care as `master.key`. They are not in
the repo in readable form, so a machine that can decrypt `production.yml.enc` is the only place
they exist.
