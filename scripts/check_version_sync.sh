#!/usr/bin/env bash
# Assert that every place a toolchain or service version is pinned agrees.
#
# A version gets spelled out in several files because different consumers read different ones:
# mise.toml drives local dev (and mise-action in CI), .ruby-version / .node-version /
# .python-version feed setup-ruby / setup-node / setup-python, the Dockerfile ARGs build the
# production image, package.json's `packageManager` field drives corepack, mise.lock records the
# exact release a floating mise.toml spec resolves to, and the `image:` tags
# in a compose file or config/deploy.yml decide what production runs versus what CI tests
# against. Nothing makes them agree on its own, so a bump that misses one file is silent: the
# image builds on a different Ruby than the tests ran on, or the suite goes green against a
# database server nobody deploys.
#
# Part of the dev-env standard (dev-hooks:dev-env-setup, v30) — run by the hk `versions` step and
# CI's `versions` job so the local and CI gates can't drift. Don't hand-edit the logic; the next
# policy change should be a plain re-copy of the template (a repo's own formatter may re-indent
# this file to local style, which is fine).
#
# Only files that exist get checked, and every skip is printed: a repo legitimately without a
# Dockerfile or a compose file passes, but its pass never looks like more coverage than it is.
# The gate reports and never rewrites a pin — which file holds the correct value is a judgement
# call (in one repo the right fix was to change production, not CI).
#
# Deliberately NOT checked: go.mod's `go` directive. It declares the *minimum* language version
# the module builds with, not the toolchain a build pins, so it is routinely — and correctly —
# older than mise.toml's `go`. Comparing them would fail healthy repos.
#
# Deliberately NOT enforced: Dockerfile style. Whether an image hardcodes `ARG NODE_VERSION` or
# derives the Node major from .node-version is a per-repo choice. This verifies that whatever
# pins exist agree, so adopting the standard never forces a Dockerfile rewrite.
#
# EVERY Dockerfile in the repo root is checked, not just the first one found. A repo
# commonly carries a production `Dockerfile` beside a `Dockerfile.dev`, and stopping at the first
# is how one of them sat on node:22 for months while .node-version, mise.toml and the production
# Dockerfile all said 24 — with this gate green the whole time, in the repo whose own docs claimed
# Node 24 "everywhere".
#
# CI's own setup steps are checked too: agreeing files prove nothing if the job that runs the
# tests installs some other version (see "CI setup steps" below).
#
# ruff is the one tool a repo can install twice: mise's copy runs in hk and CI, uv's runs under
# `uv run ruff` and in the editor hooks that prefer .venv/bin/ruff. A minor release can switch
# on new default rules, so the two copies must be the same release: uv.lock's ruff joins the
# comparison with mise's.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0
note() {
	echo "  ✗ $1"
	fail=1
}
skip() { echo "  - $1"; }

TMP=$(mktemp) || exit 1
CI_PINS=$(mktemp) || exit 1
CI_OUT=$(mktemp) || exit 1
trap 'rm -f "$TMP" "$CI_PINS" "$CI_OUT"' EXIT

# ── Toolchain pins ────────────────────────────────────────────────────────────────────
MISE=""
for f in mise.toml .mise.toml mise/config.toml .config/mise.toml .config/mise/config.toml; do
	if [ -f "$f" ]; then
		MISE=$f
		break
	fi
done
# mise writes the lock beside the config: mise/config.toml locks to mise/mise.lock, and
# .mise.toml to the root mise.lock.
LOCK=mise.lock
[ -n "$MISE" ] && LOCK=$(dirname "$MISE")/mise.lock && LOCK=${LOCK#./}

# Newline-separated, because a `for f in $DOCKERFILES` would word-split a name containing a
# space. An unmatched glob is left literal by the shell (no nullglob here), so `Dockerfile.*` in
# a repo with only a plain `Dockerfile` survives as that literal string — the `[ -f ]` guard is
# what drops it, and must not be removed. `Dockerfile` itself needs the literal dot to match
# `Dockerfile.*`, so it can never be listed twice.
#
# Excluded: editor/VCS leftovers (`Dockerfile.dev.bak`, `Dockerfile.orig`) and templates
# (`Dockerfile.j2`) — neither is a build input, and a template's `ARG NODE_VERSION={{ ... }}`
# would fail forever with no correct value to change it to.
DOCKERFILES=""
for f in Dockerfile Containerfile Dockerfile.* Containerfile.*; do
	[ -f "$f" ] || continue
	case $f in
	*.bak | *.orig | *.rej | *.save | *.swp | *.swo | *.tmp | *.disabled | *~) continue ;;
	*.example | *.sample | *.j2 | *.tpl | *.template | *.erb) continue ;;
	esac
	DOCKERFILES="$DOCKERFILES$f
"
done

# A mise config's pin for a tool: `node = "22.4.1"` and the inline table
# `ruby = { version = "4.0.2", compile = false }` under `[tools]` (the first quoted string after
# `=`), or the table `[tools.ruby]` with `version = "4.0.2"`.
read_mise() {
	[ -n "$MISE" ] || return 0
	awk -v key="$1" '
    /^[[:space:]]*\[/ {
      intools = ($0 ~ /^[[:space:]]*\[tools\][[:space:]]*$/)
      intable = ($0 ~ "^[[:space:]]*\\[tools\\.\"?" key "\"?\\][[:space:]]*$")
      next
    }
    intable && /^[[:space:]]*version[[:space:]]*=/ {
      if (match($0, /"[^"]*"/)) { print substr($0, RSTART + 1, RLENGTH - 2); exit }
    }
    !intools { next }
    {
      line = $0
      sub(/#.*/, "", line)
      if (line !~ "^[[:space:]]*\"?" key "\"?[[:space:]]*=") next
      sub(/^[^=]*=/, "", line)
      if (match(line, /"[^"]*"/)) { print substr(line, RSTART + 1, RLENGTH - 2); exit }
    }
  ' "$MISE"
}

# One Dockerfile's `ARG NAME=value` defaults, one per line, deduplicated. A multi-stage build may
# redeclare a bare `ARG NAME` to pull it into a later stage's scope; those carry no pin, so only
# `=` lines count. $1 is the file, $2 the ARG name.
#
# Strips blanks, CR and quotes but NOT newlines: `[:space:]` here used to delete the line
# separators too, which collapsed two differing defaults into one line, so `lines` could only
# ever answer 0 or 1 and the caller's "conflicting defaults" branch was unreachable. A file
# declaring 24.19.0 and 20.0.0 reported the value as "24.19.020.0.0" instead.
read_arg() {
	sed -n "s/^[[:space:]]*ARG[[:space:]]\{1,\}$2=//p" "$1" | tr -d "[:blank:]\r\"'" | sort -u
}

# package.json's `"packageManager": "pnpm@9.1.0+sha512…"` — corepack's pin, for the JS stack.
read_pkgmgr() { # $1 tool, [$2 package.json path]
	local pj=${2:-package.json}
	[ -f "$pj" ] || return 0
	sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pj" |
		head -n1 | awk -F'@' -v t="$1" 'NF > 1 && $1 == t { sub(/\+.*/, "", $2); print $2 }'
}

# `.ruby-version` may be bare (3.4.10) or prefixed (ruby-3.4.10); `.node-version` may carry a
# leading v (v22.4.1). Every form is valid for setup-* and mise, so normalise before comparing.
normalize() {
	local v
	v=$(printf '%s' "$2" | tr -d "[:space:]\"'")
	v=${v#"$1"-}
	v=${v#"$1"}
	case $v in v[0-9]*) v=${v#v} ;; esac
	printf '%s' "$v"
}

lines() { printf '%s' "$1" | grep -c .; }

# The lock's exact release for a tool: `[[tools.python]]` (or the older single-table
# `[tools.python]`) followed by `version = "3.14.6"`. It is what mise installs locally and what
# mise-action installs in CI, so it is the release every other pin is measured against.
read_lock() {
	[ -f "$LOCK" ] || return 0
	awk -v key="$1" '
    /^\[\[?tools\.("[^"]*"|[^."\]]+)\]\]?[[:space:]]*$/ {
      h = $0
      sub(/^\[\[?tools\./, "", h)
      sub(/\]\]?[[:space:]]*$/, "", h)
      gsub(/"/, "", h)
      cur = (h == key)
      next
    }
    /^\[/ { cur = 0; next }
    cur && /^version[[:space:]]*=/ {
      v = $0
      sub(/^[^=]*=[[:space:]]*"/, "", v)
      sub(/".*/, "", v)
      print v
      exit
    }
  ' "$LOCK"
}

# uv.lock's resolved release of a Python package: the `version` line of its `[[package]]` entry,
# which follows the `name` line.
read_uvlock() {
	[ -f uv.lock ] || return 0
	awk -v pkg="$1" '
    /^\[/ { cur = 0; next }
    /^name[[:space:]]*=/ {
      v = $0
      sub(/^[^=]*=[[:space:]]*"/, "", v)
      sub(/".*/, "", v)
      cur = (v == pkg)
      next
    }
    cur && /^version[[:space:]]*=/ {
      v = $0
      sub(/^[^=]*=[[:space:]]*"/, "", v)
      sub(/".*/, "", v)
      print v
      exit
    }
  ' uv.lock
}

# A full release (3.12.12, 24.11.0) rather than a line of them (3.12, 24): setup-* actions and uv
# resolve a partial version to the newest matching release on the day, so it floats in CI.
is_full() {
	local re='^[0-9]+\.[0-9]+\.[0-9]+([.+-]?[A-Za-z0-9].*)?$'
	[[ $1 =~ $re || ${1##*-} =~ $re ]]
}

# The version a file hands a setup action. `.tool-versions` carries one line per tool; go.mod's
# `toolchain` (else `go`) line is what setup-go reads. package.json and pyproject.toml name a
# range (engines, requires-python), printed as "<range>".
read_file_version() { # $1 tool, $2 file
	local v
	if [ "$2" = "$MISE" ]; then
		normalize "$1" "$(read_mise "$1")"
		return
	fi
	case $2 in
	*package.json) if [ "$1" = bun ]; then v=$(read_pkgmgr bun "$2"); else v="<range>"; fi ;;
	*pyproject.toml) v="<range>" ;;
	*.tool-versions)
		v=$(awk -v t="$1" '$1 == t || (t == "node" && $1 == "nodejs") || (t == "go" && $1 == "golang") { print $2; exit }' "$2")
		;;
	*go.mod)
		v=$(sed -n 's/^toolchain[[:space:]]\{1,\}go//p' "$2" | head -n1)
		[ -n "$v" ] || v=$(sed -n 's/^go[[:space:]]\{1,\}//p' "$2" | head -n1)
		;;
	*) v=$(grep -v '^[[:space:]]*#' "$2" | grep -m1 . || true) ;;
	esac
	case $v in
	"<range>") printf '%s' "$v" ;;
	*) normalize "$1" "$v" ;;
	esac
}

# ── CI setup steps ────────────────────────────────────────────────────────────────────
# A CI job runs the language version its setup step names — and when it names none, the
# runner's own. A pin that agrees across every file still proves nothing about CI if the setup
# step floats (`lts/*`, `3.12`), hardcodes something else, or has no version at all; setup-uv in
# particular installs uv, not Python, so on its own uv takes the runner's python3. Each step
# must read the pin: a version file naming a full release, or mise-action installing the tool
# from mise.toml in the same job. The standard tests one version, so a matrix is a failure too.
# Composite actions under .github/actions/ are walked the same way.
WORKFLOWS=""
for f in .github/workflows/*.yml .github/workflows/*.yaml .github/actions/*/action.yml .github/actions/*/action.yaml; do
	[ -f "$f" ] && WORKFLOWS="$WORKFLOWS$f
"
done

# One row per setup or mise-action step, fields separated by \037 (a tab is IFS whitespace, so
# `read` would collapse an empty field and shift every later column):
#   file, job, action, version input, version-file input, mise `install`, mise `install_args`.
# An absent input is "<none>", distinct from an empty one; an unquoted YAML float (3.10, read by
# GitHub as 3.1) is prefixed "<float>". A line-based walk, not a YAML parser: it knows jobs (or a
# composite action's `runs:`), the `steps:` list, `with:` in block or flow style, and block
# scalars — a `run: |` body is skipped, so script text that looks like a step is never one.
ci_steps() {
	awk -v f="$1" -v comp="$2" '
    function ind(s) { match(s, /^ */); return RLENGTH }
    function clean(v) {
      sub(/[[:space:]]+#.*$/, "", v)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (v ~ /^[0-9]+\.[0-9]*0$/) return "<float>" v
      if (v ~ /^".*"$/ || v ~ /^\047.*\047$/) v = substr(v, 2, length(v) - 2)
      return v
    }
    function get(k) { return (k != "" && (k in w)) ? w[k] : "<none>" }
    function flush(   vk, fk) {
      vk = fk = ""
      if (act == "actions/setup-python") { vk = "python-version"; fk = "python-version-file" }
      else if (act == "astral-sh/setup-uv") vk = "python-version"
      else if (act == "actions/setup-node") { vk = "node-version"; fk = "node-version-file" }
      else if (act == "ruby/setup-ruby") vk = "ruby-version"
      else if (act == "actions/setup-go") { vk = "go-version"; fk = "go-version-file" }
      else if (act == "oven-sh/setup-bun") { vk = "bun-version"; fk = "bun-version-file" }
      if (vk != "" || act == "jdx/mise-action" || act ~ /^\.\//)
        printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\n", f, job, act, get(vk), get(fk), get("install"), get("install_args")
      act = ""; instep = 0; withind = -1; bkey = ""
      split("", w)
    }
    BEGIN { blk = -1; withind = -1; jobind = -1; steps = -1; dash = -1 }
    {
      raw = $0
      sub(/\r$/, "", raw)
      if (raw ~ /^[[:space:]]*$/) next
      i = ind(raw)
      if (blk >= 0) {
        if (i > blk) {
          if (bkey != "") { t = raw; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t); w[bkey] = w[bkey] (w[bkey] == "" ? "" : " ") t }
          next
        }
        blk = -1; bkey = ""
      }
      if (raw ~ /^[[:space:]]*#/) next
      if (i == 0) {
        flush(); steps = -1
        if (comp) { injobs = (raw ~ /^runs:/); job = "composite"; jobind = 1000000 }
        else { injobs = (raw ~ /^jobs:/); jobind = -1 }
        next
      }
      if (!injobs) next
      if (jobind < 0) jobind = i
      if (i == jobind) {
        flush(); steps = -1
        job = raw
        sub(/^[[:space:]]*/, "", job)
        sub(/:.*/, "", job)
        next
      }
      line = raw
      keyind = i
      isdash = match(line, /^ *- +/)
      if (isdash) {
        keyind = RLENGTH
        line = substr(line, RLENGTH + 1)
      } else sub(/^ */, "", line)
      # Only a dash at the steps list own indent starts a step; leaving that list (a dash or a
      # key back at or above `steps:`) ends it, so `needs:` written as a compact list is ignored.
      if (steps >= 0) {
        if (isdash && dash < 0 && i >= steps) dash = i
        if (isdash && i == dash) { flush(); instep = 1 }
        else if ((isdash && i < dash) || (!isdash && i <= steps)) { flush(); steps = -1 }
      }
      if (!match(line, /^[A-Za-z0-9_.-]+:/)) next
      k = substr(line, 1, RLENGTH - 1)
      v = clean(substr(line, RLENGTH + 1))
      if (!instep && k == "steps") { flush(); steps = keyind; dash = -1; next }
      if (v ~ /^[|>][-+0-9]*$/) { blk = keyind; if (withind >= 0 && keyind > withind) { bkey = k; w[k] = "" } }
      if (!instep) next
      if (withind >= 0 && keyind <= withind) withind = -1
      if (withind >= 0) { if (bkey == "") w[k] = v; next }
      if (k == "with") {
        if (v ~ /^\{.*\}$/) {
          n = split(substr(v, 2, length(v) - 2), kv, ",")
          for (j = 1; j <= n; j++) if (match(kv[j], /:/)) {
            fk2 = substr(kv[j], 1, RSTART - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", fk2)
            w[fk2] = clean(substr(kv[j], RSTART + 1))
          }
        } else withind = keyind
        next
      }
      if (k == "uses") { sub(/@.*/, "", v); act = v }
    }
    END { flush() }
  ' "$1"
}

ci_rows=""
while IFS= read -r wf; do
	[ -n "$wf" ] || continue
	case $wf in .github/actions/*) comp=1 ;; *) comp=0 ;; esac
	ci_rows="$ci_rows$(ci_steps "$wf" "$comp")
"
done <<<"$WORKFLOWS"

# Does a step in this file+job use this action?
job_uses() { # $1 file, $2 job, $3 action
	local f j a
	while IFS=$'\037' read -r f j a _; do
		[ "$f" = "$1" ] && [ "$j" = "$2" ] && [ "$a" = "$3" ] && return 0
	done <<<"$ci_rows"
	return 1
}

# The file+job pairs that call a composite action (`uses: ./.github/actions/<name>`), one
# "file\037job" per line — a composite runs inside its caller's job. Step order is not checked,
# here or for mise-action within a job.
callers_of() { # $1 composite action file
	local f j a dir=${1%/action.y*ml}
	while IFS=$'\037' read -r f j a _; do
		[ "${a%/}" = "./$dir" ] && printf '%s\037%s\n' "$f" "$j"
	done <<<"$ci_rows"
}

# Does a mise-action step in this file+job install the tool? With no install_args it installs
# every mise.toml tool; with them, only the named ones (`python@3.14` counts as python).
mise_installs() { # $1 file, $2 job, $3 tool
	local f j a inst args tok toks
	[ -n "$(read_mise "$3")" ] || return 1
	while IFS=$'\037' read -r f j a _ _ inst args; do
		[ "$f" = "$1" ] && [ "$j" = "$2" ] && [ "$a" = jdx/mise-action ] || continue
		[ "$inst" = false ] && continue
		[ "$args" = "<none>" ] || [ -z "$args" ] && return 0
		read -ra toks <<<"$args"
		for tok in "${toks[@]}"; do
			[ "${tok%%@*}" = "$3" ] && return 0
		done
	done <<<"$ci_rows"
	return 1
}

# A composite action is covered when every job that calls it installs the tool with mise-action.
caller_installs() { # $1 composite action file, $2 tool
	local f j any=0
	while IFS=$'\037' read -r f j; do
		[ -n "$f" ] || continue
		any=1
		mise_installs "$f" "$j" "$2" || return 1
	done <<<"$(callers_of "$1")"
	[ "$any" = 1 ]
}

ci_ok() { echo "  ✓ $1" >>"$CI_OUT"; }
ci_bad() {
	echo "  ✗ $1" >>"$CI_OUT"
	fail=1
}

# The tool's conventional pin file, which the toolchain comparison already reads.
own_vfile() {
	case $1 in
	python) echo .python-version ;; node) echo .node-version ;; ruby) echo .ruby-version ;;
	go) echo .go-version ;; *) echo "" ;;
	esac
}

# A partial release floats: name what CI will resolve and, if the lock has it, what local runs.
floats_msg() { # $1 tool, $2 partial version
	local locked
	locked=$(read_lock "$1")
	printf 'CI resolves the newest %s.x%s; write the full release' "$2" "${locked:+, while $LOCK pins $locked}"
}

# A step reading a version file: it must exist, name a full release, and — when it is not the
# tool's own pin file, which is compared already — join the comparison.
ci_pinned=""
judge_file() { # $1 where, $2 action, $3 tool, $4 file
	local v own
	if [ ! -f "$4" ]; then
		ci_bad "$1: $2 reads $4, which does not exist"
		return
	fi
	v=$(read_file_version "$3" "$4")
	if [ "$v" = "<range>" ]; then
		own=$(own_vfile "$3")
		ci_bad "$1: $2 reads $4, which names a range, not a release — ${own:+read $own instead}${own:-pin an exact release}"
	elif [ -z "$v" ]; then
		ci_bad "$1: $2 reads $4, which names no $3 version"
	elif [[ $v != [0-9]* && $v != pypy* ]]; then
		ci_bad "$1: $2 reads $4, which names \"$v\", not a release"
	elif ! is_full "$v"; then
		ci_bad "$1: $2 reads $4 ($v) — $(floats_msg "$3" "$v")"
	else
		ci_ok "$1: $2 reads $4"
		if [ "$4" != "$(own_vfile "$3")" ] && [ "$4" != "$MISE" ] && [[ $4 != *package.json ]] && [[ $ci_pinned != *"|$3:$4|"* ]]; then
			ci_pinned="$ci_pinned|$3:$4|"
			printf '%s\t%s\t%s\n' "$3" "$4" "$v" >>"$CI_PINS"
		fi
	fi
}

nsetup=0
while IFS=$'\037' read -r f job act ver vfile inst args; do
	[ -n "$f" ] && [ "$act" != jdx/mise-action ] && [[ $act != ./* ]] || continue
	nsetup=$((nsetup + 1))
	case $act in
	actions/setup-python | astral-sh/setup-uv) tool=python ;;
	actions/setup-node) tool=node ;;
	ruby/setup-ruby) tool=ruby ;;
	actions/setup-go) tool=go ;;
	oven-sh/setup-bun) tool=bun ;;
	esac
	where="$f $job"
	[ -z "$ver" ] && ver="<none>"
	[ -z "$vfile" ] && vfile="<none>"
	if [ "$act" = ruby/setup-ruby ]; then
		# setup-ruby takes a file name in `ruby-version` itself, and `default` means "no input".
		case $ver in
		default) ver="<none>" ;;
		.* | *.toml) vfile=$ver ver="<none>" ;;
		esac
	fi
	key=${tool}-version
	if [ "$ver" = "<none>" ] && [ "$vfile" != "<none>" ]; then
		judge_file "$where" "$act" "$tool" "$vfile"
	elif [ "$ver" != "<none>" ]; then
		norm=$(normalize "$tool" "$ver")
		if [[ $ver == *\$\{\{* ]]; then
			ci_bad "$where: $act $key is an expression ($ver) — CI must run the one pinned version; read the pin file instead"
		elif [[ $ver == "<float>"* ]]; then
			ci_bad "$where: $act $key is an unquoted ${ver#<float>}, which YAML reads as a number (3.10 becomes 3.1) — quote it, or better, read the pin file"
		elif is_full "$norm"; then
			printf '%s\t%s\t%s\n' "$tool" "$where $act" "$norm" >>"$CI_PINS"
			skip "$where: $act pins $norm (compared under Toolchain)" >>"$CI_OUT"
		elif [[ $norm =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
			ci_bad "$where: $act $key is $norm — $(floats_msg "$tool" "$norm")"
		else
			ci_bad "$where: $act $key is \"$ver\", which floats — CI runs whatever is newest, not what local pins; read the pin file instead"
		fi
	elif [ "$tool" = python ] && [ -f .python-version ]; then
		judge_file "$where" "$act" "$tool" .python-version
	elif [ "$act" = astral-sh/setup-uv ] && job_uses "$f" "$job" actions/setup-python; then
		ci_ok "$where: setup-uv uses setup-python's interpreter"
	elif [ "$tool" = ruby ] && [ -f .ruby-version ]; then
		judge_file "$where" "$act" "$tool" .ruby-version
	elif [ "$tool" = ruby ] && [ -f .tool-versions ] && [ -n "$(read_file_version ruby .tool-versions)" ]; then
		judge_file "$where" "$act" "$tool" .tool-versions
	elif mise_installs "$f" "$job" "$tool"; then
		ci_ok "$where: $tool from $MISE via mise-action"
	elif [ "$job" = composite ] && caller_installs "$f" "$tool"; then
		ci_ok "$where: $tool from $MISE via mise-action in every calling job"
	elif [ "$tool" = ruby ] && [ -n "$(read_mise ruby)" ]; then
		judge_file "$where" "$act" "$tool" "$MISE"
	elif [ "$tool" = python ]; then
		ci_bad "$where: $act names no Python, so the job runs the runner's python3 — pin python in mise.toml and install it with mise-action in this job (or add .python-version)"
	elif [ "$tool" = ruby ]; then
		ci_bad "$where: $act names no version and finds no .ruby-version, .tool-versions or mise.toml ruby — add .ruby-version"
	else
		ci_bad "$where: $act names no version, so the job runs whatever $tool the runner has — read the pin file (${tool}-version-file) or install it with mise-action"
	fi
done <<<"$ci_rows"

# Sources for one tool, compared as a set. A mise.toml spec, a .<lang>-version file and a
# Dockerfile ARG may name a line (`3.12`) that an exact release (`3.12.12`) satisfies; mise.lock,
# packageManager and what CI reads name a release, and releases must be equal.
n=0
src_label=()
src_ver=()
src_spec=()
add_source() { # $1 label, $2 version, $3 "spec" if a line of releases may satisfy it
	src_label[n]=$1
	src_ver[n]=$2
	src_spec[n]=${3:-}
	n=$((n + 1))
}
compatible() { # $1 ver a, $2 a is spec, $3 ver b, $4 b is spec
	[ "$1" = "$3" ] && return 0
	[ -n "$2" ] && [[ $3 == "$1".* ]] && return 0
	[ -n "$4" ] && [[ $1 == "$3".* ]] && return 0
	return 1
}
# Every pair must agree — against the first source alone, two releases can each satisfy a loose
# spec and still differ. Sets `shown` to the version the ✓ line names: the most specific one.
compare_sources() {
	local k j ex=0
	mismatch=0
	for ((k = 1; k < n; k++)); do
		for ((j = 0; j < k; j++)); do
			if ! compatible "${src_ver[k]}" "${src_spec[k]}" "${src_ver[j]}" "${src_spec[j]}"; then
				note "${src_label[k]} (${src_ver[k]}) != ${src_label[j]} (${src_ver[j]})"
				mismatch=1
				break
			fi
		done
		[ "${#src_ver[k]}" -gt "${#src_ver[ex]}" ] && ex=$k
	done
	shown=${src_ver[ex]}
	return 0
}

echo "Toolchain:"
[ -n "$MISE" ] || skip "no mise.toml or other mise config, so no mise pins to cross-check"
[ -n "$DOCKERFILES" ] || skip "no Dockerfile, so no image-build ARGs to cross-check"

# tool | version file (empty = no conventional one) | Dockerfile ARG | uv.lock package
while IFS='|' read -r tool vfile arg uvpkg; do
	[ -n "$tool" ] || continue
	n=0
	src_label=()
	src_ver=()
	src_spec=()
	floating=""

	if [ -n "$vfile" ] && [ -f "$vfile" ]; then
		ver=$(read_file_version "$tool" "$vfile")
		[ -n "$ver" ] && add_source "$vfile" "$ver" spec
	fi

	raw=$(read_mise "$tool")
	if [ -n "$raw" ]; then
		# "latest"/"lts" and backend-prefixed specs (aqua:…, ruby-build:…) name no version of their
		# own; mise.lock, when present, is the release they resolved to.
		case $raw in
		*:*) floating=$raw ;;
		*[0-9]*) add_source "$MISE $tool" "$(normalize "$tool" "$raw")" spec ;;
		*) floating=$raw ;;
		esac
		locked=$(read_lock "$tool")
		if [ -n "$locked" ]; then
			add_source "$LOCK $tool" "$(normalize "$tool" "$locked")"
			floating=""
		fi
	fi

	raw=$(read_pkgmgr "$tool")
	[ -n "$raw" ] && add_source "package.json packageManager" "$(normalize "$tool" "$raw")"

	if [ -n "$uvpkg" ]; then
		raw=$(read_uvlock "$uvpkg")
		[ -n "$raw" ] && add_source "uv.lock $uvpkg" "$raw"
	fi

	# Each Dockerfile is its own source, labelled by name: with two of them the ✓ line lists both,
	# and a mismatch says which file to fix rather than just "Dockerfile".
	while IFS= read -r dockerfile; do
		[ -n "$dockerfile" ] && [ -n "$arg" ] || continue
		raw=$(read_arg "$dockerfile" "$arg")
		case "$(lines "$raw")" in
		0) ;;
		1) add_source "$dockerfile ARG $arg" "$(normalize "$tool" "$raw")" spec ;;
		*) note "$dockerfile declares ARG $arg with conflicting defaults: $(printf '%s' "$raw" | tr '\n' ' ')" ;;
		esac
	done <<<"$DOCKERFILES"

	while IFS=$'\t' read -r t label v; do
		[ "$t" = "$tool" ] && add_source "$label" "$v"
	done <"$CI_PINS"

	# A floating mise spec is only worth mentioning when some other file does pin the tool —
	# on its own it is the standard's normal state, not a gap.
	floating_note=""
	[ -n "$floating" ] && floating_note=" ($MISE spec is \"$floating\", no fixed version to compare)"

	case $n in
	0) ;; # this repo pins the tool nowhere — nothing to say about it
	1) skip "$tool: pinned only in ${src_label[0]} (${src_ver[0]})$floating_note, nothing to cross-check" ;;
	*)
		[ -n "$floating" ] && skip "$tool: $MISE spec is \"$floating\" (no fixed version), not compared"
		compare_sources
		all_srcs=$(printf '%s, ' "${src_label[@]}")
		[ "$mismatch" = 0 ] && echo "  ✓ $tool $shown — ${all_srcs%, }"
		;;
	esac
done <<'TOOLS'
ruby|.ruby-version|RUBY_VERSION
node|.node-version|NODE_VERSION
python|.python-version|PYTHON_VERSION
go|.go-version|GO_VERSION
yarn||YARN_VERSION
pnpm||PNPM_VERSION
npm||NPM_VERSION
bun||BUN_VERSION
ruff|||ruff
TOOLS

echo
echo "CI setup steps:"
if [ -z "$WORKFLOWS" ]; then
	skip "no workflows, nothing to check"
elif [ "$nsetup" -eq 0 ]; then
	if printf '%s' "$ci_rows" | grep -q $'\037jdx/mise-action\037'; then
		skip "no setup-* steps; the workflows install their toolchain with mise-action ($LOCK)"
	else
		skip "no language setup steps in the workflows"
	fi
fi
cat "$CI_OUT"

# ── Service image tags ────────────────────────────────────────────────────────────────
# CI has to exercise the services production actually runs, or the suite goes green against a
# database nobody deploys. Deployment manifests differ per repo (a compose file, Kamal's
# config/deploy.yml, a devcontainer compose), so discover whichever are present instead of
# hardcoding one, and compare every file that pins a given image against the others. An image
# named in only one file is not drift (CI may legitimately not need Redis), so it is reported
# but never fails.
echo
echo "Service image tags:"

FILES=""
nfiles=0
for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml \
	config/deploy.yml config/deploy.yaml \
	.devcontainer/compose.yml .devcontainer/compose.yaml \
	.devcontainer/docker-compose.yml .devcontainer/docker-compose.yaml \
	.github/workflows/*.yml .github/workflows/*.yaml; do
	if [ -f "$f" ]; then
		FILES="$FILES$f
"
		nfiles=$((nfiles + 1))
	fi
done

if [ "$nfiles" -eq 0 ]; then
	skip "no compose / deploy / workflow files, nothing to cross-check"
else
	# `image: mysql:8.4`, `image: "mysql:8.4"`, `image: mysql:8.4@sha256:…` (CI pins by digest, so
	# match only the tag). Commented-out and templated (${…}, {{…}}, <%…%>) images are skipped, as
	# are untagged ones (a bare `image: acme/app` pins nothing).
	printf '%s' "$FILES" | while IFS= read -r f; do
		[ -n "$f" ] || continue
		awk -v f="$f" '
      {
        line = $0
        sub(/#.*/, "", line)
        if (line !~ /^[[:space:]]*-?[[:space:]]*image:[[:space:]]*[^[:space:]]/) next
        sub(/^[[:space:]]*-?[[:space:]]*image:[[:space:]]*/, "", line)
        gsub(/["\047]/, "", line)
        sub(/[[:space:]].*$/, "", line)
        sub(/@.*$/, "", line)
        if (line ~ /\$|\{\{|<%/) next
        nc = split(line, part, ":")
        if (nc < 2) next
        tag = part[nc]
        repo = substr(line, 1, length(line) - length(tag) - 1)
        if (repo == "" || tag == "") next
        sub(/^docker\.io\//, "", repo)
        sub(/^library\//, "", repo)
        print repo "\t" tag "\t" f
      }
    ' "$f"
	done | sort -u >"$TMP"

	if [ ! -s "$TMP" ]; then
		skip "no tagged \`image:\` pins in the $nfiles compose/deploy/workflow file(s) present"
	elif ! awk -F'\t' '
    {
      if (!($1 in seen)) { seen[$1] = 1; order[++nk] = $1 }
      fkey = $1 SUBSEP $3
      if (!(fkey in fseen)) { fseen[fkey] = 1; nf[$1]++; files[$1] = files[$1] (files[$1] ? ", " : "") $3 }
      tkey = $1 SUBSEP $2
      if (!(tkey in tseen)) { tseen[tkey] = 1; nt[$1]++ }
      onefile[$1] = $3
      onetag[$1] = $2
      detail[$1] = detail[$1] (detail[$1] ? ", " : "") $3 " (" $2 ")"
    }
    END {
      bad = 0
      for (i = 1; i <= nk; i++) {
        k = order[i]
        if (nf[k] < 2)
          printf "  - %s: pinned only in %s (%s), nothing to cross-check\n", k, onefile[k], onetag[k]
        else if (nt[k] == 1)
          printf "  ✓ %s %s — %s\n", k, onetag[k], files[k]
        else {
          printf "  ✗ %s tags disagree: %s\n", k, detail[k]
          bad = 1
        }
      }
      if (bad) print "    CI must exercise the services production runs — pick the right value and set it everywhere."
      exit bad
    }
  ' "$TMP"; then
		fail=1
	fi
fi

[ "$fail" -eq 0 ] || echo "Version pins disagree — fix the file(s) named above."
exit "$fail"
