#!/bin/sh
# test-check-downstream-versions.sh
#
# Regression suite for check-downstream-versions.sh.
#
# The defect under test: the checker used to read VOCAB_VERSIONS as a plain file
# path from the working tree, so a checkout sitting on an unmerged feature branch
# reported that branch's proposed numbers as "Canonical" and every downstream
# repo as drifted against a number nobody had ratified.
#
# Every assertion below is paired with a negative control: the same scenario is
# replayed against the PREVIOUS version of the checker (read out of git history)
# and must produce the wrong answer. A test that passes against both versions
# proves nothing and is a bug in this file.
#
# Usage: ./scripts/test-check-downstream-versions.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NEW_SCRIPT="$SCRIPT_DIR/check-downstream-versions.sh"

PASSED=0
FAILED=0
SKIPPED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }
skip() { SKIPPED=$((SKIPPED + 1)); echo "  SKIP  $1  ($2)"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Extract the previous checker from git history, for negative controls.
# ---------------------------------------------------------------------------
OLD_SCRIPT="$WORK/old-check.sh"
OLD_AVAILABLE=1
if ! git -C "$SPEC_ROOT" show "origin/main:scripts/check-downstream-versions.sh" > "$OLD_SCRIPT" 2>/dev/null; then
  if ! git -C "$SPEC_ROOT" show "main:scripts/check-downstream-versions.sh" > "$OLD_SCRIPT" 2>/dev/null; then
    OLD_AVAILABLE=0
  fi
fi
[ "$OLD_AVAILABLE" = "1" ] && chmod +x "$OLD_SCRIPT"

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

mkrepo() {
  # mkrepo <path> <versions-content>
  _p="$1"; _c="$2"
  mkdir -p "$_p"
  git -C "$_p" init -b main >/dev/null 2>&1
  printf '%s\n' "$_c" > "$_p/VOCAB_VERSIONS"
  git -C "$_p" add -A >/dev/null 2>&1
  git -C "$_p" -c user.email=t@t -c user.name=t commit -m init >/dev/null 2>&1
}

branch_bump() {
  # branch_bump <path> <branch> <new-versions-content>
  _p="$1"; _b="$2"; _c="$3"
  git -C "$_p" checkout -b "$_b" >/dev/null 2>&1
  printf '%s\n' "$_c" > "$_p/VOCAB_VERSIONS"
  git -C "$_p" add -A >/dev/null 2>&1
  git -C "$_p" -c user.email=t@t -c user.name=t commit -m bump >/dev/null 2>&1
}

# build_dev <name> -> echoes path to a synthetic DEV_ROOT containing spec/
build_dev() {
  _d="$WORK/$1"
  mkdir -p "$_d"
  echo "$_d"
}

install_checker() {
  # install_checker <spec_path> <script>
  mkdir -p "$1/scripts"
  cp "$2" "$1/scripts/check-downstream-versions.sh"
  chmod +x "$1/scripts/check-downstream-versions.sh"
}

VER_MAIN="core=3.3
health=2.4
clinical=1.12"

VER_BRANCH="core=3.4
health=2.5
clinical=1.13"

VER_OLD_DOWNSTREAM="core=3.3
health=2.4
clinical=1.9"

echo ""
echo "check-downstream-versions.sh regression suite"
echo "============================================="
echo ""

# ===========================================================================
echo "Scenario A: spec checkout on an UNMERGED branch that bumps all three vocabs"
# ===========================================================================
DEV_A="$(build_dev devA)"
mkrepo "$DEV_A/spec" "$VER_MAIN"
branch_bump "$DEV_A/spec" "feat/health-v2.5" "$VER_BRANCH"
mkrepo "$DEV_A/cascade-cli" "$VER_MAIN"

install_checker "$DEV_A/spec" "$NEW_SCRIPT"
OUT_NEW="$(sh "$DEV_A/spec/scripts/check-downstream-versions.sh" 2>&1)"
RC_NEW=$?

# A1: canonical must be main's numbers, not the branch's
if echo "$OUT_NEW" | grep -q "core = 3.3"; then
  pass "A1 canonical core reads 3.3 from main, not 3.4 from the branch"
else
  fail "A1 canonical core reads 3.3 from main" "got: $(echo "$OUT_NEW" | grep -i 'core =')"
fi

# A1-NEG: the previous checker must get this WRONG
if [ "$OLD_AVAILABLE" = "1" ]; then
  install_checker "$DEV_A/spec" "$OLD_SCRIPT"
  OUT_OLD="$(sh "$DEV_A/spec/scripts/check-downstream-versions.sh" 2>&1)"
  RC_OLD=$?
  install_checker "$DEV_A/spec" "$NEW_SCRIPT"
  if echo "$OUT_OLD" | grep -q "core = 3.4"; then
    pass "A1-NEG previous checker launders the branch (reports canonical core = 3.4)"
  else
    fail "A1-NEG previous checker should launder the branch" "old checker did not report 3.4; this test proves nothing. old output: $OUT_OLD"
  fi
else
  skip "A1-NEG previous checker negative control" "could not read scripts/check-downstream-versions.sh from main"
fi

# A2: loud, machine-greppable warning that the working tree is not canonical
if echo "$OUT_NEW" | grep -q "NOT YET CANONICAL"; then
  pass "A2 warns loudly that the working tree is ahead of main"
else
  fail "A2 warns loudly that the working tree is ahead of main" "no NOT YET CANONICAL banner in output"
fi

# A3: the warning names the branch and every pending vocab
A3_OK=1
for tok in "feat/health-v2.5" "core: working tree=3.4" "health: working tree=2.5" "clinical: working tree=1.13"; do
  echo "$OUT_NEW" | grep -q "$tok" || { A3_OK=0; A3_MISS="$tok"; }
done
if [ "$A3_OK" = "1" ]; then
  pass "A3 warning names the branch and all three pending vocab bumps"
else
  fail "A3 warning names the branch and all three pending bumps" "missing token: $A3_MISS"
fi

# A3-NEG: the previous checker emits no such warning
if [ "$OLD_AVAILABLE" = "1" ]; then
  if echo "$OUT_OLD" | grep -q "NOT YET CANONICAL"; then
    fail "A3-NEG previous checker should have no pending-branch warning" "old checker already warned; test proves nothing"
  else
    pass "A3-NEG previous checker emits no pending-branch warning"
  fi
else
  skip "A3-NEG previous checker warning control" "old script unavailable"
fi

# A4: exit code is non-zero while a bump is unmerged
if [ "$RC_NEW" -ne 0 ]; then
  pass "A4 exits non-zero while the spec bump is unmerged (rc=$RC_NEW)"
else
  fail "A4 exits non-zero while the spec bump is unmerged" "rc=0"
fi

# A5: a downstream repo matching MAIN is not reported as drifted
if echo "$OUT_NEW" | grep -q "\[cascade-cli\] UP TO DATE"; then
  pass "A5 downstream repo matching main is UP TO DATE (not drifted against a branch)"
else
  fail "A5 downstream repo matching main is UP TO DATE" "got: $(echo "$OUT_NEW" | grep cascade-cli)"
fi

# A5-NEG: previous checker reports it as drifted against the unratified branch
if [ "$OLD_AVAILABLE" = "1" ]; then
  if echo "$OUT_OLD" | grep -q "\[cascade-cli\] DRIFT DETECTED"; then
    pass "A5-NEG previous checker falsely drifts cascade-cli against the branch"
  else
    fail "A5-NEG previous checker should falsely drift cascade-cli" "old output: $(echo "$OUT_OLD" | grep cascade-cli)"
  fi
else
  skip "A5-NEG previous checker drift control" "old script unavailable"
fi

echo ""
# ===========================================================================
echo "Scenario B: clean main, downstream in sync (distinctness: must differ from A)"
# ===========================================================================
DEV_B="$(build_dev devB)"
mkrepo "$DEV_B/spec" "$VER_MAIN"
mkrepo "$DEV_B/cascade-cli" "$VER_MAIN"
install_checker "$DEV_B/spec" "$NEW_SCRIPT"
OUT_B="$(sh "$DEV_B/spec/scripts/check-downstream-versions.sh" 2>&1)"
RC_B=$?

if [ "$RC_B" -eq 0 ] && echo "$OUT_B" | grep -q "All downstream repos are in sync"; then
  pass "B1 clean main + synced downstream exits 0 and reports in sync"
else
  fail "B1 clean main + synced downstream exits 0" "rc=$RC_B"
fi

if echo "$OUT_B" | grep -q "NOT YET CANONICAL"; then
  fail "B2 no pending-branch warning when on clean main" "banner appeared on a clean main"
else
  pass "B2 no pending-branch warning when on clean main"
fi

# Distinctness: A and B are genuinely different inputs and produce different output
if [ "$OUT_NEW" != "$OUT_B" ]; then
  pass "B3 distinctness: unmerged-branch output differs from clean-main output"
else
  fail "B3 distinctness" "identical output for two different repo states"
fi

echo ""
# ===========================================================================
echo "Scenario C: downstream genuinely behind"
# ===========================================================================
DEV_C="$(build_dev devC)"
mkrepo "$DEV_C/spec" "$VER_MAIN"
mkrepo "$DEV_C/cascade-cli" "$VER_OLD_DOWNSTREAM"
install_checker "$DEV_C/spec" "$NEW_SCRIPT"
OUT_C="$(sh "$DEV_C/spec/scripts/check-downstream-versions.sh" 2>&1)"
RC_C=$?

if [ "$RC_C" -ne 0 ] && echo "$OUT_C" | grep -q "clinical: repo=1.9  spec=1.12"; then
  pass "C1 real downstream drift is still detected and named"
else
  fail "C1 real downstream drift is detected" "rc=$RC_C; $(echo "$OUT_C" | grep clinical)"
fi

echo ""
# ===========================================================================
echo "Scenario D: downstream sync exists but is UNMERGED"
# ===========================================================================
DEV_D="$(build_dev devD)"
mkrepo "$DEV_D/spec" "$VER_MAIN"
mkrepo "$DEV_D/cascade-cli" "$VER_OLD_DOWNSTREAM"
branch_bump "$DEV_D/cascade-cli" "chore/sync-clinical" "$VER_MAIN"
install_checker "$DEV_D/spec" "$NEW_SCRIPT"
OUT_D="$(sh "$DEV_D/spec/scripts/check-downstream-versions.sh" 2>&1)"
RC_D=$?

if echo "$OUT_D" | grep -q "UNMERGED"; then
  pass "D1 downstream sync on an unmerged branch is reported as UNMERGED"
else
  fail "D1 downstream unmerged sync is flagged" "$(echo "$OUT_D" | grep cascade-cli)"
fi

if [ "$RC_D" -ne 0 ]; then
  pass "D2 unmerged downstream sync does not count as done (rc=$RC_D)"
else
  fail "D2 unmerged downstream sync must not exit 0" "rc=0"
fi

# D-NEG: previous checker calls the unmerged downstream sync UP TO DATE
if [ "$OLD_AVAILABLE" = "1" ]; then
  install_checker "$DEV_D/spec" "$OLD_SCRIPT"
  OUT_D_OLD="$(sh "$DEV_D/spec/scripts/check-downstream-versions.sh" 2>&1)"
  RC_D_OLD=$?
  install_checker "$DEV_D/spec" "$NEW_SCRIPT"
  if [ "$RC_D_OLD" -eq 0 ] && echo "$OUT_D_OLD" | grep -q "\[cascade-cli\] UP TO DATE"; then
    pass "D-NEG previous checker calls the unmerged downstream sync UP TO DATE (rc=0)"
  else
    fail "D-NEG previous checker should call it UP TO DATE" "rc=$RC_D_OLD; $(echo "$OUT_D_OLD" | grep cascade-cli)"
  fi
else
  skip "D-NEG previous checker unmerged-downstream control" "old script unavailable"
fi

echo ""
# ===========================================================================
echo "Scenario E: escape hatches"
# ===========================================================================
install_checker "$DEV_A/spec" "$NEW_SCRIPT"
OUT_E1="$(VOCAB_ALLOW_WORKTREE=1 sh "$DEV_A/spec/scripts/check-downstream-versions.sh" 2>&1)"
if echo "$OUT_E1" | grep -q "core = 3.4"; then
  pass "E1 VOCAB_ALLOW_WORKTREE=1 restores working-tree reads for tarball checkouts"
else
  fail "E1 VOCAB_ALLOW_WORKTREE=1 reads the working tree" "$(echo "$OUT_E1" | grep -i 'core =')"
fi

OUT_E2="$(VOCAB_CANONICAL_REF=feat/health-v2.5 sh "$DEV_A/spec/scripts/check-downstream-versions.sh" 2>&1)"
if echo "$OUT_E2" | grep -q "core = 3.4" && echo "$OUT_E2" | grep -q "spec @ feat/health-v2.5"; then
  pass "E2 VOCAB_CANONICAL_REF pins an explicit ref and labels the source"
else
  fail "E2 VOCAB_CANONICAL_REF pins an explicit ref" "$(echo "$OUT_E2" | head -4)"
fi

# E3: a non-git directory falls back to the working tree with a stderr warning
DEV_E="$(build_dev devE)"
mkdir -p "$DEV_E/spec"
printf '%s\n' "$VER_MAIN" > "$DEV_E/spec/VOCAB_VERSIONS"
mkrepo "$DEV_E/cascade-cli" "$VER_MAIN"
install_checker "$DEV_E/spec" "$NEW_SCRIPT"
ERR_E3="$(sh "$DEV_E/spec/scripts/check-downstream-versions.sh" 2>&1 >/dev/null)"
OUT_E3="$(sh "$DEV_E/spec/scripts/check-downstream-versions.sh" 2>/dev/null)"
if echo "$ERR_E3" | grep -q "WARNING: canonical versions were read from the spec WORKING TREE" \
   && echo "$OUT_E3" | grep -q "core = 3.3"; then
  pass "E3 non-git checkout falls back to working tree and warns on stderr"
else
  fail "E3 non-git checkout warns on stderr" "stderr: $ERR_E3"
fi

echo ""
# ===========================================================================
echo "Scenario F: determinism"
# ===========================================================================
R1="$(cd / && sh "$DEV_C/spec/scripts/check-downstream-versions.sh" 2>&1)"
R2="$(cd "$WORK" && sh "$DEV_C/spec/scripts/check-downstream-versions.sh" 2>&1)"
R3="$(cd "$DEV_C" && sh "$DEV_C/spec/scripts/check-downstream-versions.sh" 2>&1)"
if [ "$R1" = "$R2" ] && [ "$R2" = "$R3" ]; then
  pass "F1 identical output from three separate processes in three working directories"
else
  fail "F1 determinism across cwd" "outputs differ"
fi
if [ "$R1" != "$OUT_B" ]; then
  pass "F2 distinctness: the deterministic output is not a constant (drifted != synced)"
else
  fail "F2 distinctness" "drifted and synced repos produced identical output"
fi

echo ""
echo "============================================="
TOTAL=$((PASSED + FAILED + SKIPPED))
echo "passed=$PASSED  failed=$FAILED  skipped=$SKIPPED  total=$TOTAL"
[ "$FAILED" -eq 0 ] || exit 1
