#!/usr/bin/env bash
# Shared jscpd runner — the single home of the version-cooldown policy, called by both
# the hk pre-commit/`check` gate and the CI audit job so the two can't drift.
# Part of the dev-env standard (dev-hooks:dev-env-setup, v14); don't edit the logic by
# hand — the next policy change should be a plain re-copy of the template (a repo's own
# formatter may re-indent this file to local style; that's fine).
#
# Usage: run-jscpd.sh [--require] <formats>
#   <formats>   comma-separated jscpd format list for -f (e.g. "python,bash")
#   --require   fail when jscpd can't run at all (CI passes this; pre-commit omits it so
#               a commit is never blocked by an unreachable registry)
#
# Version policy: track latest with a 4-day cooldown (never run a release < 4 days old —
# supply-chain seasoning), floored at v5 (the major .jscpd.json targets) so it can't
# regress to v4 while v5 is still maturing. Online → resolve the newest version >= 4 days
# old (`npx --before`), fall back to `latest` when that lands below the v5 floor, then run
# it (the real gate — exit reflects duplication). Offline → run the cached jscpd. No cache
# + offline → warn and pass (or fail under --require).
set -u

require=0
if [ "${1:-}" = "--require" ]; then
  require=1
  shift
fi
formats="${1:?usage: run-jscpd.sh [--require] <formats>}"

cutoff=$(date -u -d '4 days ago' +%F 2>/dev/null || date -u -v-4d +%F)
if curl -sf -m 3 https://registry.npmjs.org/ >/dev/null 2>&1; then
  ver=$(npx --before="$cutoff" --yes jscpd --version 2>/dev/null | awk 'END{print $NF}')
  case $ver in
    '' | 0.* | 1.* | 2.* | 3.* | 4.*) ver=latest ;;
  esac
  npx --yes jscpd@"$ver" . -f "$formats"
elif npx --offline jscpd --version >/dev/null 2>&1; then
  npx --offline jscpd . -f "$formats"
else
  if [ "$require" = 1 ]; then
    echo 'jscpd unavailable (offline, no cache) and --require set; failing' >&2
    exit 1
  fi
  echo 'jscpd unavailable offline; skipping duplication check'
fi
