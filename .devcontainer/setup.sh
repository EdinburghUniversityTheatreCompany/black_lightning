#!/bin/sh
set -e

echo "=== Fixing bundle cache permissions ==="
sudo chown -R "$(whoami)" /bundle

echo "=== Installing gems ==="
bundle install

echo "=== Installing JS packages ==="
yarn install

echo "=== Waiting for MySQL to be ready ==="
until mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" --skip-ssl -e "SELECT 1" >/dev/null 2>&1; do
  echo "  MySQL not ready yet, retrying in 2s..."
  sleep 2
done
echo "  MySQL is ready."

DB_EXISTS=$(mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" --skip-ssl \
  -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='bedlam_blacklightning_development';" \
  -s -N 2>/dev/null || echo "0")

if [ "$DB_EXISTS" -gt 0 ]; then
  echo "=== Database exists, running migrations ==="
  bin/rails db:migrate
elif [ -f .devcontainer/dump.sql.gz ] && [ "$(zcat .devcontainer/dump.sql.gz | wc -c)" -gt 0 ]; then
  echo "=== Importing database dump ==="
  zcat .devcontainer/dump.sql.gz | mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" --skip-ssl
  bin/rails db:migrate
  echo "  Import complete."
else
  echo "=== Setting up fresh database ==="
  bin/rails db:prepare
fi

echo "=== Done! Run 'bin/dev' to start the server ==="
