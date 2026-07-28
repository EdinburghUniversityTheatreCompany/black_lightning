#!/bin/bash
set -euo pipefail

# This is not used directly but just as a backup. It lives in deploy's home/backups folder (~/backups/job.sh) and is called by the crontab on the EUSA Host VM
# Why? Because it needs duplicacy, rclone and mysqldump, which are all available on the host.
# This folder has a hidden .duplicacy folder that contains the duplicacy repository config.

# You need to define the following in a file called .my.cnf in the home folder:
# [client]
# user=root
# password=<the mysql root password from the mysql.key file or the bitwarden

# MySQL is a Kamal accessory on the private `kamal` docker network and publishes
# no port (removed deliberately in 6dfb22ee), so 127.0.0.1 on the HOST cannot
# reach it. That went unnoticed because the running container kept a stale port
# mapping from before that commit, until it was recreated on 2026-07-28 and this
# script started failing. Go through the container instead -- no exposed port.
# --single-transaction takes a consistent InnoDB snapshot without locking the
# site out of its own tables for the length of the dump.
# \042 = double quote, \047 = single quote; octal avoids nesting quotes here.
MYSQL_PW=$(sed -n 's/^password[[:space:]]*=[[:space:]]*//p' ~/.my.cnf | tr -d '\042\047\r\n')
docker exec -e MYSQL_PWD="$MYSQL_PW" blacklightning-mysql \
  mysqldump -uroot --protocol=TCP -h127.0.0.1 \
  --all-databases --single-transaction --routines --triggers --events \
  > black-lightning-db-backup.sql

/home/deploy/bin/duplicacy backup

/home/deploy/bin/duplicacy prune -keep 7:90
/home/deploy/bin/duplicacy prune

# Do the Backblaze part of the backup.
echo "Backing up the database to Backblaze by cloning the bucket from wasabi"
rclone copy wasabi-database:bedlam-theatre-website-database-backups backblaze-database:bedlam-website-database-backups --fast-list --stats-log-level NOTICE --stats 30m

echo "Mirroring all storage files from Wasabi to Backblaze"
rclone copy wasabi-database:bedlam-theatre-website backblaze-storage:bedlam-website-mirror --fast-list --stats-log-level NOTICE --stats 30m --exclude "variants/*"

# Do not delete the dump so the latest one is always available.

# Remove the database dump and notify that the backup was succesful.
curl https://api.honeybadger.io/v1/check_in/NeI9y6
