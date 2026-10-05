# Production MySQL 8.0 → 8.4 upgrade

**Status: DONE, 2026-07-28.** Production runs **8.4.11**, with its data directory moved
out of the Capistrano release tree to `/var/lib/blacklightning/mysql`. Verified: all 79
tables and 477,011 rows identical before and after. Kept as the record, and as the
procedure if it ever has to be repeated.

## What actually happened

Rehearsed first against the real backup in a throwaway container: restore into 8.0,
restart on 8.4, confirm the upgrade and that the data survived. That rehearsal also
settled the question the env-var confusion below raised — a container booted on an
existing data directory with a *completely different* `MYSQL_ROOT_PASSWORD` could not
authenticate with it, while the real password still worked. The variable is inert once
the data directory exists (the entrypoint sets `DATABASE_ALREADY_EXISTS` and skips the
whole init branch), so a reboot cannot change or lose the password.

Three things bit during the real run, all worth knowing:

1. **`docker stop` never shut MySQL down cleanly.** The container carries
   `--restart unless-stopped`, and mysqld did not finish within Docker's grace period —
   twice ending in exit 137 (SIGKILL). What worked: `docker update --restart=no` first,
   *then* `mysqladmin shutdown`, which exits 0 with "Shutdown complete" in the log and
   stays down. Without the policy change, a clean shutdown is immediately undone by
   Docker restarting the container.
2. **The relative volume path came from a `cd` in `~deploy/.bashrc`.** Bash sources
   `.bashrc` for non-interactive ssh too, so it set Kamal's working directory, and Kamal
   expands relative paths against it. That line is now removed, which also moved Kamal's
   own `.kamal` state (including env files holding secrets) out of the release tree and
   into `/home/deploy`.
3. **The accessory's `MYSQL_ROOT_PASSWORD` was stale** — captured when the container
   booted three weeks earlier, before a credential rotation, so it no longer matched the
   app's. Harmless (see above), and the reboot refreshed it.

## The host's three hard constraints

Read this before running anything heavy on `bdlm-eusa-ed-ac-uk`. They compound, and on
2026-07-28 they took the site down for roughly an hour.

| Constraint | Consequence |
|---|---|
| **1.7 GB RAM** (cannot be raised) | Shared by MySQL, Puma (running Solid Queue in-process) and kamal-proxy. The kernel OOM-killed **dockerd itself**, which killed every container. |
| **XFS formatted `ftype=0`** | Docker *cannot* use `overlay2` and falls back to **`fuse-overlayfs`**, which runs in userspace and is several times slower. Every `docker` command is slow; `docker system df` times out entirely. Only fixable by reformatting, or giving `/var/lib/docker` its own correctly-formatted volume. |
| **44 GB disk** | Was at 92% before this cleanup; both XFS and overlay degrade badly when near full. |

**What that means in practice:** never run two heavy I/O operations at once. The outage came
from a `docker container prune` left running from a timed-out ssh call, a second detached
prune started on top of it, plus a 7 GB `rm -rf` and a journal vacuum — load hit 47, the box
swapped itself to a standstill, and sshd could not complete a handshake. Any one of those
alone would have been fine.

The daily prune (`/usr/local/sbin/docker-prune`, 06:30 via `/etc/cron.d/docker-prune`) is
built for this: `flock` so runs can never overlap, `ionice -c3 nice -n19` so it yields, and
06:30 to stay clear of the 04:17 backup which rclones two buckets and can run long.

**The nightly backup depends on the accessory container name.** It runs
`docker exec blacklightning-mysql mysqldump …` (see `bash_scripts/backups.sh`) because the
accessory publishes no port. If that container is ever renamed, the backup silently fails.

Cleared during the same session: the legacy nginx/Passenger stack and the **root cron entry
that restarted it every 5 minutes** — it was holding ports 80/443, so which server answered
the site was decided by boot-order race rather than configuration. Also the orphaned
`certbot renew` cron (certbot manages no certificates; kamal-proxy does its own TLS), a
world-readable CloudFlare origin private key under `/opt/nginx/certs`, and stale
`config/master.key` copies left by Capistrano. Disk went 92% → 68%.

---

## The original plan follows

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
