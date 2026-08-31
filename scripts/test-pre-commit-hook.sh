#!/bin/sh
# test-pre-commit-hook.sh
#
# Regression suite for scripts/hooks/pre-commit.
#
# The defect under test: SKIP_VERSION_CHECK=1 exited the whole hook before
# anything ran. The flag advertises itself as skipping "vocabulary version
# checks", and the footer offers it "only for non-vocabulary housekeeping
# commits", but the blanket `exit 0` also skipped the "VOCAB_VERSIONS not
# staged" error and the shapes-file warning.
#
# That is reachable without anyone misusing it. The dct:modified == today rule
# false-positives on `git commit --amend` after midnight and on staging one day
# and committing the next; the contributor then follows the hook's OWN printed
# advice, sets SKIP_VERSION_CHECK=1, and the TTL bump lands with VOCAB_VERSIONS
# still at the old value -- exactly the drift check-downstream-versions.sh
# exists to catch, permitted by the documented escape hatch rather than by
# --no-verify.
#
# Case 1 is the defining assertion: with the flag set and VOCAB_VERSIONS not
# staged, the hook must still block. Every assertion is paired with a control,
# and the flag's ADVERTISED behaviour is asserted too (case 3), so scoping it
# cannot quietly turn into disabling it.
#
# Hermetic: throwaway git repositories in a temp dir. No network, and the
# repository this runs in is never committed to.
#
# Usage: ./scripts/test-pre-commit-hook.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/hooks/pre-commit"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }

if [ ! -f "$HOOK" ]; then
  echo "ERROR: $HOOK not found, so this suite would test nothing."
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

TTL_PATH="ontologies/testvocab/v1/testvocab.ttl"
SHAPES_PATH="ontologies/testvocab/v1/testvocab.shapes.ttl"

# Build a throwaway repo whose HEAD holds testvocab at version $1 with
# dct:modified $2, plus a VOCAB_VERSIONS file. Echoes the repo path.
scratch_repo() {
  name="$1"; head_version="$2"; head_date="$3"
  dir="$WORK/$name"
  mkdir -p "$dir/ontologies/testvocab/v1"
  git init -q "$dir"
  git -C "$dir" config user.email "suite@example.invalid"
  git -C "$dir" config user.name "Regression Suite"
  git -C "$dir" config commit.gpgsign false

  cat > "$dir/$TTL_PATH" <<EOF
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix dct: <http://purl.org/dc/terms/> .

<https://ns.cascadeprotocol.org/testvocab/v1> a owl:Ontology ;
    dct:modified "$head_date"^^xsd:date ;
    owl:versionInfo "$head_version" .
EOF
  cat > "$dir/$SHAPES_PATH" <<'EOF'
# shapes for testvocab
EOF
  echo "testvocab=$head_version" > "$dir/VOCAB_VERSIONS"

  git -C "$dir" add -A
  git -C "$dir" commit -q -m "base"
  echo "$dir"
}

# Rewrite the staged TTL to version $2 with dct:modified $3, and stage it.
stage_bump() {
  dir="$1"; version="$2"; modified="$3"
  cat > "$dir/$TTL_PATH" <<EOF
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix dct: <http://purl.org/dc/terms/> .

<https://ns.cascadeprotocol.org/testvocab/v1> a owl:Ontology ;
    dct:modified "$modified"^^xsd:date ;
    owl:versionInfo "$version" .
EOF
  git -C "$dir" add "$TTL_PATH"
}

stage_vocab_versions() {
  dir="$1"; version="$2"
  echo "testvocab=$version" > "$dir/VOCAB_VERSIONS"
  git -C "$dir" add VOCAB_VERSIONS
}

# Run the hook inside $1 with the environment in $2 ("skip" or "plain").
run_hook() {
  dir="$1"; mode="$2"
  if [ "$mode" = "skip" ]; then
    ( cd "$dir" && SKIP_VERSION_CHECK=1 bash "$HOOK" 2>&1 )
  else
    ( cd "$dir" && bash "$HOOK" 2>&1 )
  fi
}

TODAY="$(date +%F)"

echo ""
echo "=========================================================="
echo "  pre-commit hook regression suite"
echo "  hook: $HOOK"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 0. Syntax control: a hook that does not parse tests nothing below.
# ---------------------------------------------------------------------------
echo ""
echo "0. Syntax control"

if bash -n "$HOOK" 2>/dev/null; then
  pass "the hook parses under bash"
else
  fail "the hook does not parse" "$(bash -n "$HOOK" 2>&1)"
fi

# ---------------------------------------------------------------------------
# 1. THE DEFINING CASE. SKIP_VERSION_CHECK=1 must NOT waive the VOCAB_VERSIONS
#    check. This is the drift the flag used to permit.
# ---------------------------------------------------------------------------
echo ""
echo "1. SKIP_VERSION_CHECK=1 still enforces VOCAB_VERSIONS staging"

DIR="$(scratch_repo skip-no-vocab 1.0 2026-01-01)"
stage_bump "$DIR" 1.1 2026-01-01      # stale date: the realistic reason to reach for the flag
OUT="$(run_hook "$DIR" skip)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "blocked despite SKIP_VERSION_CHECK=1 (exit $STATUS)"
else
  fail "SKIP_VERSION_CHECK=1 waived the VOCAB_VERSIONS check" "$OUT"
fi
if echo "$OUT" | grep -q "VOCAB_VERSIONS"; then
  pass "names VOCAB_VERSIONS as the reason"
else
  fail "blocked without naming VOCAB_VERSIONS" "$OUT"
fi

# ---------------------------------------------------------------------------
# 2. Negative control for case 1: with VOCAB_VERSIONS staged, the same commit
#    under the same flag passes. So the failure above is the unstaged ledger
#    and not the flag having become inert.
# ---------------------------------------------------------------------------
echo ""
echo "2. Negative control: VOCAB_VERSIONS staged, same flag, must pass"

DIR="$(scratch_repo skip-with-vocab 1.0 2026-01-01)"
stage_bump "$DIR" 1.1 2026-01-01
stage_vocab_versions "$DIR" 1.1
OUT="$(run_hook "$DIR" skip)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "passes with VOCAB_VERSIONS staged (exit 0)"
else
  fail "blocked even with VOCAB_VERSIONS staged" "$OUT"
fi

# ---------------------------------------------------------------------------
# 3. The flag must still DO what it advertises. A stale dct:modified is the
#    false positive it exists for, so it must block without the flag and pass
#    with it. Without this, scoping the flag could silently become disabling it.
# ---------------------------------------------------------------------------
echo ""
echo "3. The flag still waives the dct:modified check it advertises"

DIR="$(scratch_repo stale-date 1.0 2026-01-01)"
stage_bump "$DIR" 1.1 2026-01-01
stage_vocab_versions "$DIR" 1.1
OUT="$(run_hook "$DIR" plain)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "a stale dct:modified blocks without the flag (exit $STATUS)"
else
  fail "a stale dct:modified did not block" "$OUT"
fi
if echo "$OUT" | grep -q "dct:modified"; then
  pass "names dct:modified"
else
  fail "blocked without naming dct:modified" "$OUT"
fi

OUT="$(run_hook "$DIR" skip)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "the same commit passes with the flag set (exit 0)"
else
  fail "the flag no longer waives the check it advertises" "$OUT"
fi

# ---------------------------------------------------------------------------
# 4. The flag must also waive the owl:versionInfo assertion it names -- and
#    STILL enforce VOCAB_VERSIONS while doing so. An unbumped version is the
#    case where the old code's `continue` skipped the ledger check too.
# ---------------------------------------------------------------------------
echo ""
echo "4. An unbumped owl:versionInfo under the flag still needs VOCAB_VERSIONS"

DIR="$(scratch_repo unbumped 1.0 2026-01-01)"
stage_bump "$DIR" 1.0 "$TODAY"        # version deliberately unchanged
OUT="$(run_hook "$DIR" skip)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "blocked on the unstaged ledger (exit $STATUS)"
else
  fail "an unbumped version under the flag skipped VOCAB_VERSIONS" "$OUT"
fi
if echo "$OUT" | grep -q "VOCAB_VERSIONS"; then
  pass "names VOCAB_VERSIONS"
else
  fail "blocked without naming VOCAB_VERSIONS" "$OUT"
fi

# Control: without the flag the same tree blocks on the VERSION instead, so the
# flag is demonstrably still waiving that assertion.
OUT="$(run_hook "$DIR" plain)"
STATUS=$?
if echo "$OUT" | grep -q "owl:versionInfo unchanged"; then
  pass "control: without the flag it blocks on owl:versionInfo"
else
  fail "without the flag it did not report the unchanged version" "$OUT"
fi

# ---------------------------------------------------------------------------
# 5. Scope control: no ontology TTL staged means the hook is a no-op, flag or
#    not. Scoping the flag must not make unrelated commits start failing.
# ---------------------------------------------------------------------------
echo ""
echo "5. Scope control: a commit staging no ontology TTL passes"

DIR="$(scratch_repo no-ttl 1.0 2026-01-01)"
echo "notes" > "$DIR/README.md"
git -C "$DIR" add README.md
OUT="$(run_hook "$DIR" plain)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "no ontology TTL staged, hook passes (exit 0)"
else
  fail "the hook blocked a commit touching no ontology" "$OUT"
fi
OUT="$(run_hook "$DIR" skip)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "same, with the flag set (exit 0)"
else
  fail "the hook blocked a non-ontology commit under the flag" "$OUT"
fi

# ---------------------------------------------------------------------------
# 6. A clean vocabulary commit passes with no flag at all. If this fails, every
#    assertion above is measuring a hook that blocks everything.
# ---------------------------------------------------------------------------
echo ""
echo "6. Positive control: a correct vocabulary commit passes unaided"

DIR="$(scratch_repo clean 1.0 2026-01-01)"
stage_bump "$DIR" 1.1 "$TODAY"
stage_vocab_versions "$DIR" 1.1
OUT="$(run_hook "$DIR" plain)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "bump + today's date + staged ledger passes (exit 0)"
else
  fail "a correct vocabulary commit was blocked" "$OUT"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=========================================================="
echo "  passed:  $PASSED"
echo "  failed:  $FAILED"
echo "  total:   $((PASSED + FAILED))"
echo "=========================================================="
echo ""

[ "$FAILED" -eq 0 ] || exit 1
exit 0
