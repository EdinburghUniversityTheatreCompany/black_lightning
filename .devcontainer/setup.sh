#!/bin/sh
set -e

echo "=== Fixing bundle cache permissions ==="
sudo chown -R "$(whoami)" /bundle

echo "=== Installing gems ==="
bundle install

echo "=== Installing JS packages ==="
yarn install

echo "=== Waiting for MySQL to be ready ==="
until bin/rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" 2>/dev/null; do
  echo "  MySQL not ready yet, retrying in 2s..."
  sleep 2
done
echo "  MySQL is ready."

if [ -f .devcontainer/dump.sql.gz ]; then
  echo "=== Importing database dump ==="
  zcat .devcontainer/dump.sql.gz | mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD"
  bin/rails db:migrate
  echo "  Import complete."
else
  echo "=== Setting up fresh database ==="
  bin/rails db:prepare
fi

echo "=== Done! Run 'bin/dev' to start the server ==="
