# The production host

Read this before running anything heavy on `bdlm-eusa-ed-ac-uk`. Its limits compound, and on
2026-07-28 they took the site down for about an hour.

## Three hard constraints

| Constraint | Consequence |
|---|---|
| **1.7 GB RAM** (cannot be raised) | Shared by MySQL, Puma (running Solid Queue in-process) and kamal-proxy. The kernel has OOM-killed **dockerd itself**, which killed every container. |
| **XFS formatted `ftype=0`** | Docker cannot use `overlay2` and falls back to **`fuse-overlayfs`**, which runs in userspace and is several times slower. Every `docker` command is slow; `docker system df` times out. Only fixable by reformatting, or by giving `/var/lib/docker` its own correctly formatted volume. |
| **44 GB disk** | Both XFS and overlay degrade badly near full. It was at 92% before the July cleanup and 68% after. |

**Never run two heavy I/O jobs at once.** The outage came from a `docker container prune` left
running by a timed-out ssh call, a second detached prune on top of it, a 7 GB `rm -rf` and a
journal vacuum. Load hit 47, the box swapped to a standstill and sshd could not complete a
handshake. Any one of them alone would have been fine.

## Scheduled jobs on the host

- **Docker prune, 06:30** (`/usr/local/sbin/docker-prune`, run from `/etc/cron.d/docker-prune`).
  It takes a `flock` so runs never overlap, runs under `ionice -c3 nice -n19` so it yields, and
  sits at 06:30 to stay clear of the backup.
- **Backup, 04:17** (deploy's crontab runs `~/backups/job.sh`; `bash_scripts/backups.sh` is the
  copy in this repo). It rclones two buckets and can run long. It dumps the database with
  `docker exec blacklightning-mysql mysqldump …` because the MySQL accessory publishes no port.
  **Rename that container and the backup fails silently.**

## Traps

- **Stopping MySQL cleanly.** `docker stop` does not: the container carries
  `--restart unless-stopped`, mysqld overruns Docker's grace period and is SIGKILLed (exit 137).
  Run `docker update --restart=no` first, then `mysqladmin shutdown`. It exits 0, logs
  "Shutdown complete" and stays down. Skip the policy change and Docker restarts the container
  straight away.
- **Nothing may `cd` in `~deploy/.bashrc`.** Bash sources it for non-interactive ssh too, so it
  sets Kamal's working directory, and Kamal resolves relative volume paths against it. A `cd`
  there once put the MySQL data directory and Kamal's own `.kamal` state (env files holding
  secrets) inside the release tree. The data directory now lives at
  `/var/lib/blacklightning/mysql`.
- **`MYSQL_ROOT_PASSWORD` does nothing once the data directory exists.** The entrypoint skips its
  whole init branch, so setting the variable never changes the root password and a reboot cannot
  lose it. A stale value in the accessory's environment is harmless.
