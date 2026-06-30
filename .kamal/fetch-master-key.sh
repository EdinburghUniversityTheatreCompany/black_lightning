#!/bin/bash
set -e

if [ -f config/credentials/master.key ]; then
  cat config/credentials/master.key
elif command -v bw >/dev/null 2>&1; then
  echo "Fetching master key from Bitwarden..." >&2
  SECRETS=$(kamal secrets fetch --adapter bitwarden --account it@bedlamtheatre.co.uk Black_Lightning_Production_Master_Key)
  kamal secrets extract Black_Lightning_Production_Master_Key $SECRETS
else
  echo "ERROR: Rails master key not found. Either:" >&2
  echo "  1. Create config/credentials/master.key with the master key from Bitwarden" >&2
  echo "  2. Install the Bitwarden CLI: https://bitwarden.com/help/cli/" >&2
  exit 1
fi
