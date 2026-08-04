#!/bin/sh
# check-downstream-versions.sh
#
# Compares the canonical vocabulary versions against every downstream repository.
#
# CANONICAL SOURCE OF TRUTH: the VOCAB_VERSIONS file as it exists on the
# integration branch (`origin/main`, falling back to `main`) -- NOT the working
# tree. A checkout sitting on an unmerged feature branch would otherwise launder
# that branch's proposed version numbers into "canonical", and every downstream
# repo would be reported as drifted against a number no one has ratified.
#
# The same rule is applied to each downstream repo: its VOCAB_VERSIONS is read
# from its own integration branch, so an unmerged sync branch is reported as
# UNMERGED rather than silently counted as done.
#
# Overrides:
#   VOCAB_CANONICAL_REF=<ref>   use <ref> instead of origin/main / main
#   VOCAB_ALLOW_WORKTREE=1      read working-tree files instead of git refs
#                               (for tarball checkouts / CI without full history)
#
# Usage: ./scripts/check-downstream-versions.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEV_ROOT="$(cd "$SPEC_ROOT/.." && pwd)"

SPEC_VERSIONS_FILE="$SPEC_ROOT/VOCAB_VERSIONS"
ALLOW_WORKTREE="${VOCAB_ALLOW_WORKTREE:-0}"

warn() {
  echo "$@" >&2
}

# resolve_ref <repo_path>
# Echoes the integration ref to read VOCAB_VERSIONS from, or nothing if the
# path is not a git repository / has no such ref.
resolve_ref() {
  _repo="$1"
  git -C "$_repo" rev-parse --git-dir >/dev/null 2>&1 || return 1

  if [ -n "${VOCAB_CANONICAL_REF:-}" ]; then
    if git -C "$_repo" rev-parse --verify --quiet "$VOCAB_CANONICAL_REF" >/dev/null 2>&1; then
      echo "$VOCAB_CANONICAL_REF"
      return 0
    fi
    return 1
  fi

  for _candidate in origin/main main origin/master master; do
    if git -C "$_repo" rev-parse --verify --quiet "$_candidate" >/dev/null 2>&1; then
      echo "$_candidate"
      return 0
    fi
  done
  return 1
}

# read_versions <repo_path> <out_file>
# Writes the comment-stripped VOCAB_VERSIONS body to <out_file>.
# Echoes a human-readable description of where it came from.
# Returns non-zero if no VOCAB_VERSIONS could be read at all.
read_versions() {
  _repo="$1"
  _out="$2"

  if [ "$ALLOW_WORKTREE" != "1" ]; then
    _ref="$(resolve_ref "$_repo")"
    if [ -n "$_ref" ] && git -C "$_repo" show "$_ref:VOCAB_VERSIONS" > "$_out.raw" 2>/dev/null; then
      grep -v '^#' "$_out.raw" | grep -v '^[[:space:]]*$' > "$_out"
      rm -f "$_out.raw"
      echo "$_ref"
      return 0
    fi
    rm -f "$_out.raw"
  fi

  if [ -f "$_repo/VOCAB_VERSIONS" ]; then
    grep -v '^#' "$_repo/VOCAB_VERSIONS" | grep -v '^[[:space:]]*$' > "$_out"
    echo "working tree"
    return 0
  fi

  return 1
}

# ---------------------------------------------------------------------------
# Canonical versions, read from spec's integration branch
# ---------------------------------------------------------------------------

SPEC_CANONICAL="$(mktemp)"
SPEC_SOURCE="$(read_versions "$SPEC_ROOT" "$SPEC_CANONICAL")"
if [ -z "$SPEC_SOURCE" ]; then
  echo "Error: could not read VOCAB_VERSIONS from $SPEC_ROOT (tried git refs and working tree)" >&2
  rm -f "$SPEC_CANONICAL"
  exit 1
fi

if [ "$SPEC_SOURCE" = "working tree" ] && [ "$ALLOW_WORKTREE" != "1" ]; then
  warn ""
  warn "!! WARNING: canonical versions were read from the spec WORKING TREE."
  warn "!! No integration ref (origin/main / main) was resolvable here, so these"
  warn "!! numbers are whatever this checkout happens to contain and are NOT"
  warn "!! proven to be ratified. Fetch the repo or set VOCAB_CANONICAL_REF."
fi

echo ""
echo "Canonical vocab versions (spec @ $SPEC_SOURCE):"
while IFS='=' read -r key val; do
  [ -n "$key" ] || continue
  echo "  $key = $val"
done < "$SPEC_CANONICAL"
echo ""

# ---------------------------------------------------------------------------
# Loud warning when the spec working tree proposes versions main has not ratified
# ---------------------------------------------------------------------------

pending_spec=0
if [ "$SPEC_SOURCE" != "working tree" ] && [ -f "$SPEC_VERSIONS_FILE" ]; then
  SPEC_WORKTREE="$(mktemp)"
  grep -v '^#' "$SPEC_VERSIONS_FILE" | grep -v '^[[:space:]]*$' > "$SPEC_WORKTREE"

  pending_lines=""
  while IFS='=' read -r vocab wt_ver; do
    [ -n "$vocab" ] || continue
    canon_ver=$(grep "^${vocab}=" "$SPEC_CANONICAL" | cut -d= -f2 | head -1)
    [ -n "$canon_ver" ] || canon_ver="ABSENT"
    if [ "$wt_ver" != "$canon_ver" ]; then
      pending_lines="${pending_lines}!!   $vocab: working tree=$wt_ver  $SPEC_SOURCE=$canon_ver\n"
    fi
  done < "$SPEC_WORKTREE"
  rm -f "$SPEC_WORKTREE"

  if [ -n "$pending_lines" ]; then
    pending_spec=1
    branch=$(git -C "$SPEC_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
    echo "!! ============================================================"
    echo "!! SPEC WORKING TREE IS AHEAD OF $SPEC_SOURCE -- NOT YET CANONICAL"
    echo "!! ============================================================"
    echo "!!   branch: ${branch:-unknown}"
    printf "%b" "$pending_lines"
    echo "!!"
    echo "!! These versions are PROPOSED, not ratified. Downstream repos below"
    echo "!! are compared against $SPEC_SOURCE. Merge this branch, then re-run."
    echo ""
  fi
fi

# ---------------------------------------------------------------------------
# Downstream comparison
# ---------------------------------------------------------------------------

DOWNSTREAM_REPOS="cascade-cli sdk-typescript sdk-python cascade-agent conformance cascadeprotocol.org cascade-sdk-swift"
any_drift=0

for repo in $DOWNSTREAM_REPOS; do
  repo_path="$DEV_ROOT/$repo"

  if [ ! -d "$repo_path" ]; then
    echo "[$repo] NOT FOUND at $repo_path"
    continue
  fi

  repo_versions="$(mktemp)"
  repo_source="$(read_versions "$repo_path" "$repo_versions")"
  if [ -z "$repo_source" ]; then
    echo "[$repo] MISSING VOCAB_VERSIONS file"
    any_drift=1
    rm -f "$repo_versions"
    continue
  fi

  drift_lines=""
  while IFS='=' read -r vocab spec_ver; do
    [ -n "$vocab" ] || continue
    repo_ver=$(grep "^${vocab}=" "$repo_versions" | cut -d= -f2 | head -1)
    [ -n "$repo_ver" ] || repo_ver="MISSING"
    if [ "$spec_ver" != "$repo_ver" ]; then
      note=""
      # If the repo's own working tree already carries the canonical value, the
      # sync exists but is unmerged. Say so instead of implying no work was done.
      if [ "$repo_source" != "working tree" ] && [ -f "$repo_path/VOCAB_VERSIONS" ]; then
        wt_ver=$(grep "^${vocab}=" "$repo_path/VOCAB_VERSIONS" | cut -d= -f2 | head -1)
        if [ "$wt_ver" = "$spec_ver" ]; then
          note="  (working tree has $wt_ver -- UNMERGED)"
        fi
      fi
      drift_lines="${drift_lines}  $vocab: repo=$repo_ver  spec=$spec_ver${note}\n"
    fi
  done < "$SPEC_CANONICAL"
  rm -f "$repo_versions"

  if [ -z "$drift_lines" ]; then
    echo "[$repo] UP TO DATE  (read from $repo_source)"
  else
    echo "[$repo] DRIFT DETECTED  (read from $repo_source):"
    printf "%b" "$drift_lines"
    any_drift=1
  fi
done

rm -f "$SPEC_CANONICAL"

echo ""
if [ "$pending_spec" = "1" ]; then
  echo "Spec has UNMERGED version bumps. Downstream sync is blocked until they merge."
  exit 1
elif [ "$any_drift" = "1" ]; then
  echo "Action required: update VOCAB_VERSIONS in drifted repos and implement missing vocabulary support."
  exit 1
else
  echo "All downstream repos are in sync."
fi
