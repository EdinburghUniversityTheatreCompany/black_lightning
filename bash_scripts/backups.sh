# This is not used directly but just as a backup. It lives in deploy's home/backups folder (~/backups/job.sh) and is called by the crontab on the EUSA Host VM
# Why? Because it needs duplicacy, rclone and mysqldump, which are all available on the host.
# This folder has a hidden .duplicacy folder that contains the duplicacy repository config.

# You need to define the following in a file called .my.cnf in the home folder:
# [client]
# user=root
# password=<the mysql root password from the mysql.key file or the bitwarden

mysqldump -h 127.0.0.1--all-databases > black-lightning-db-backup.sql

/home/deploy/bin/duplicacy backup

/home/deploy/bin/duplicacy prune -keep 7:90
/home/deploy/bin/duplicacy prune

# Do the Backblaze part of the backup.
echo "Backing up the database to Backblaze by cloning the bucket from wasabi"
rclone copy wasabi-database:bedlam-theatre-website-database-backups backblaze-database:bedlam-website-database-backups --fast-list --stats-log-level NOTICE --stats 30m

echo "Mirroring all storage files from Wasabi to Backblaze"
rclone copy wasabi-database:bedlam-theatre-website backblaze-storage:bedlam-website-mirror --fast-list --stats-log-level NOTICE --stats 30m --exclude "variants/*"

# Remove the database dump and notify that the backup was succesful.
rm black-lightning-db-backup.sql
curl https://api.honeybadger.io/v1/check_in/NeI9y6

