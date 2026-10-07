#!/usr/bin/env bash
# Two small repo rules, run by the hk steps in hk.pkl and by CI.
#   check_repo_rules.sh exec-bits | dockerfile-node

set -u
cd "$(dirname "$0")/.." || exit 1

# A shebang script must be mode 100755 in the git index: with core.fileMode=false a local
# chmod +x never reaches git, and clones get binstubs that die with exit 126.
exec_bits() {
	local bad
	bad=$(git ls-files -s | awk -F'\t' '$1 ~ /^100644/ { if ((getline line < $2) > 0 && line ~ /^#!/) print $2; close($2) }')
	[ -z "$bad" ] && return 0
	echo "Shebang scripts missing the executable bit in the git index. Fix: git update-index --chmod=+x <file>"
	echo "$bad"
	return 1
}

# The Dockerfile derives the Node major from .node-version, so check_version_sync.sh has no static
# pin to compare. This keeps it that way: no hardcoded major, no `ARG NODE_VERSION`.
dockerfile_node() {
	local fail=0
	grep -qF 'setup_$(cut -d. -f1 < .node-version)' Dockerfile || { echo "prod Dockerfile must derive the Node major from .node-version, not hardcode it"; fail=1; }
	! grep -q '^ARG NODE_VERSION=' Dockerfile || { echo "remove hardcoded ARG NODE_VERSION from Dockerfile; derive it from .node-version"; fail=1; }
	return "$fail"
}

case "${1:-}" in
exec-bits) exec_bits ;;
dockerfile-node) dockerfile_node ;;
*)
	echo "usage: $0 exec-bits|dockerfile-node" >&2
	exit 2
	;;
esac
