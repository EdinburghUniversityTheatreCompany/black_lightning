#!/bin/sh
set -e

# Named volumes mount owned by root; hand them to the vscode user before use.
echo "=== Fixing cache permissions ==="
sudo chown -R "$(whoami)" /bundle "$MISE_DATA_DIR"

# mise (mise.toml + mise.lock) owns the toolchain. Trust the bind-mounted config,
# then install the pinned Ruby, Node, and dev tools. Ruby is a precompiled portable
# build (mise `compile = false`, jdx/ruby), so the first run downloads it in seconds
# rather than compiling from source; it is cached on the mise-data volume regardless.
echo "=== Installing toolchain via mise (Ruby, Node, hk, ...) ==="
mise trust --yes
# `mise install` also runs the corepack-enable postinstall hook (see mise.toml), which makes
# the pnpm version pinned in package.json's `packageManager` field available via corepack.
mise install

echo "=== Installing git hooks (hk) ==="
mise exec -- hk install

echo "=== Installing gems ==="
mise exec -- bundle install

echo "=== Installing JS packages ==="
mise exec -- pnpm install

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
  mise exec -- bin/rails db:migrate
elif [ -f .devcontainer/dump.sql.gz ] && [ "$(zcat .devcontainer/dump.sql.gz | wc -c)" -gt 0 ]; then
  echo "=== Importing database dump ==="
  zcat .devcontainer/dump.sql.gz | mysql -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" --skip-ssl
  mise exec -- bin/rails db:migrate
  echo "  Import complete."
else
  echo "=== Setting up fresh database ==="
  mise exec -- bin/rails db:prepare
fi

echo "=== Done! Run 'bin/dev' to start the server ==="
