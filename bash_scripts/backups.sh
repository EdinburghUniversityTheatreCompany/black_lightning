#!/bin/bash
set -euo pipefail

# A copy of ~/backups/job.sh on the EUSA host VM, run there by cron because it needs the host's
# duplicacy, rclone and mysqldump. That folder's hidden .duplicacy holds the repository config.

# You need to define the following in a file called .my.cnf in the home folder:
# [client]
# user=root
# password=<the mysql root password from the mysql.key file or the bitwarden

# MySQL is a Kamal accessory publishing no port, so the host cannot reach it on 127.0.0.1.
# --single-transaction: a consistent snapshot without locking the site out for the dump.
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

# Notify Honeybadger that the backup succeeded.
curl https://api.honeybadger.io/v1/check_in/NeI9y6
