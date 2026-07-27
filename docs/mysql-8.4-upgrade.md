# Production MySQL 8.0 → 8.4 upgrade

**Status: not yet done.** Production still runs 8.0. This is the plan, not a record.

## Why

| Environment | Version | Source |
|---|---|---|
| **Production** | **8.0** | `config/deploy.yml` accessory |
| CI | 8.4 (SHA-pinned) | `.github/workflows/ci.yml` |
| Devcontainer | 8.4 | `.devcontainer/compose.yaml` |

Two problems, one fix:

1. **8.0 reached end of life on 30 April 2026.** Production has been on an unsupported
   server since then — no security patches. 8.4 is LTS until April 2032.
2. **Nothing tests against what production runs.** CI and dev are on 8.4, production on
   8.0, so the safety net covers a *newer* server than the one it protects. 8.4 changed
   defaults and removed deprecated behaviour, so the gap hides both false passes and false
   failures.

It went unnoticed because the version lives in a Kamal **accessory** — outside the app
image, untouched by a normal `kamal deploy`, and not covered by the `versions` drift job
that guards Ruby and Node.

## Before you start

The app connects as `root` (`config/database.yml` production reads `DATABASE_USERNAME` /
`MYSQL_ROOT_PASSWORD`), and the accessory sets `MYSQL_ROOT_HOST: "%"`.

1. **Check the auth plugin — this is the one that bites.** 8.4 removes built-in
   `mysql_native_password`; it survives only as a plugin that is *not loaded by default*.
   Any account still using it cannot connect after the upgrade.

   ```sh
   kamal accessory exec mysql --reuse \
     "mysql -uroot -p\$MYSQL_ROOT_PASSWORD -e \
      'SELECT user, host, plugin FROM mysql.user;'"
   ```

   Anything reporting `mysql_native_password` must be migrated **before** the upgrade:

   ```sql
   ALTER USER 'root'@'%' IDENTIFIED WITH caching_sha2_password BY '<password>';
   ```

2. **Run the upgrade checker.**

   ```sh
   kamal accessory exec mysql --reuse \
     "mysqlcheck -uroot -p\$MYSQL_ROOT_PASSWORD --all-databases --check-upgrade"
   ```

3. **Take a backup you have actually restored.** A dump that has never been restored is not
   a backup. Dump, copy it off the host, and restore it into a throwaway 8.4 container to
   confirm both that it restores and that the app's schema survives the upgrade.

## The point of no return

**8.4 rewrites the data dictionary and there is no supported downgrade.** Once the server
starts on 8.4, going back to 8.0 means restoring the backup — losing everything written
since. Do not start this without step 3 above.

## Upgrade

1. Put the app in maintenance if a short write outage matters.
2. Change the accessory image:

   ```diff
   -    image: mysql:8.0
   +    image: mysql:8.4
   ```

3. Reboot the accessory (a normal `kamal deploy` does **not** touch accessories — this is
   the step that actually performs the upgrade):

   ```sh
   kamal accessory reboot mysql
   ```

4. Watch it come up and complete its upgrade before sending traffic:

   ```sh
   kamal accessory logs mysql -f
   ```

## Verify

```sh
kamal accessory exec mysql --reuse "mysql -uroot -p\$MYSQL_ROOT_PASSWORD -e 'SELECT VERSION();'"
kamal app exec --reuse "bin/rails runner 'puts ActiveRecord::Base.connection.select_value(%(SELECT VERSION()))'"
```

Then exercise a real read/write path — the reimbursements portal is the most
database-heavy surface — and check Honeybadger for connection errors.

## Afterwards

Close the loop so this cannot drift again: add MySQL to the `versions` job in
`.github/workflows/ci.yml` (and the matching `hk` step — CLAUDE.md notes the two are kept
in sync by hand), asserting the major.minor in `config/deploy.yml`,
`.github/workflows/ci.yml` and `.devcontainer/compose.yaml` all agree. That job already
guards Ruby and Node the same way; MySQL was simply never added.

It is deliberately not added yet: the check would fail today, since production is the
odd one out until this upgrade is done.
