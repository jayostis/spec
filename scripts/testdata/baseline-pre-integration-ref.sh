#!/bin/sh
# check-downstream-versions.sh
# Reads the canonical VOCAB_VERSIONS from spec/ and compares it against
# the VOCAB_VERSIONS files in each downstream repository.
# Reports any repos that are behind.
#
# Usage: ./scripts/check-downstream-versions.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEV_ROOT="$(cd "$SPEC_ROOT/.." && pwd)"

SPEC_VERSIONS="$SPEC_ROOT/VOCAB_VERSIONS"
if [ ! -f "$SPEC_VERSIONS" ]; then
  echo "Error: VOCAB_VERSIONS not found at $SPEC_VERSIONS"
  exit 1
fi

echo ""
echo "Canonical vocab versions (spec):"
grep -v '^#' "$SPEC_VERSIONS" | grep -v '^$' | while IFS='=' read -r key val; do
  echo "  $key = $val"
done
echo ""

DOWNSTREAM_REPOS="cascade-cli sdk-typescript sdk-python cascade-agent conformance cascadeprotocol.org cascade-sdk-swift"
any_drift=0

for repo in $DOWNSTREAM_REPOS; do
  repo_path="$DEV_ROOT/$repo"
  versions_file="$repo_path/VOCAB_VERSIONS"

  if [ ! -d "$repo_path" ]; then
    echo "[$repo] NOT FOUND at $repo_path"
    continue
  fi

  if [ ! -f "$versions_file" ]; then
    echo "[$repo] MISSING VOCAB_VERSIONS file"
    any_drift=1
    continue
  fi

  drift_lines=""
  tmp_spec=$(mktemp)
  grep -v '^#' "$SPEC_VERSIONS" | grep -v '^$' > "$tmp_spec"
  while IFS='=' read -r vocab spec_ver; do
    repo_ver=$(grep "^${vocab}=" "$versions_file" | cut -d= -f2 | head -1)
    if [ -z "$repo_ver" ]; then
      repo_ver="MISSING"
    fi
    if [ "$spec_ver" != "$repo_ver" ]; then
      drift_lines="${drift_lines}  $vocab: repo=$repo_ver  spec=$spec_ver\n"
    fi
  done < "$tmp_spec"
  rm -f "$tmp_spec"

  if [ -z "$drift_lines" ]; then
    echo "[$repo] UP TO DATE"
  else
    echo "[$repo] DRIFT DETECTED:"
    printf "%b\n" "$drift_lines"
    any_drift=1
  fi
done

echo ""
if [ "$any_drift" = "1" ]; then
  echo "Action required: update VOCAB_VERSIONS in drifted repos and implement missing vocabulary support."
  exit 1
else
  echo "All downstream repos are in sync."
fi
