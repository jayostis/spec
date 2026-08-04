#!/bin/sh
# test-check-downstream-versions.sh
#
# Regression suite for check-downstream-versions.sh.
#
# Every assertion that proves a fix is paired with a NEGATIVE CONTROL: the same
# scenario replayed against a frozen copy of the checker from before that fix,
# which must produce the wrong answer. A test that passes against both versions
# proves nothing and is a bug in this file.
#
# The frozen copies live in scripts/testdata/ and are deliberately NOT read out
# of git history. A negative control that reads "the previous version" from a
# moving ref such as origin/main stops being a control the moment the fix merges:
# the ref then holds the FIXED script, the control can no longer fail, and the
# suite goes red for a reason that has nothing to do with the code under test.
# The frozen copies never move, so these controls keep their meaning forever.
#
# Do not "fix", reformat, or modernise anything in scripts/testdata/. Those files
# are defect specimens. Their bugs are the point.
#
# Usage: ./scripts/test-check-downstream-versions.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NEW_SCRIPT="$SCRIPT_DIR/check-downstream-versions.sh"

# Frozen specimens.
#   BASE_PRE_REF   -- read canonical versions from the WORKING TREE, so an
#                     unmerged branch laundered its numbers into "canonical".
#   BASE_PRE_FETCH -- never fetched (verdicts computed from possibly-stale
#                     remote-tracking refs) and skipped a missing repo without
#                     affecting the exit code.
#
# Provenance -- each specimen is a byte-for-byte copy of the checker as it stood
# at the named commit. Verify with `git hash-object <file>`:
#
#   baseline-pre-integration-ref.sh
#     from acbd319746c1940454889c99138a47cd419771b0
#     blob 473ed11c4f655bfe383055a0e8a1d89147791260
#
#   baseline-pre-fetch-and-missing-repo.sh
#     from 57111668a5093a2a8e842e18418d6e97d7d1cf15
#     blob 63c243a4a9d99e39043904dbd21d5cec115b8fd8
BASE_PRE_REF="$SCRIPT_DIR/testdata/baseline-pre-integration-ref.sh"
BASE_PRE_FETCH="$SCRIPT_DIR/testdata/baseline-pre-fetch-and-missing-repo.sh"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }

# A missing specimen must abort the suite, not skip an assertion. A skipped
# negative control is an unproven fix wearing a green tick.
for _f in "$NEW_SCRIPT" "$BASE_PRE_REF" "$BASE_PRE_FETCH"; do
  if [ ! -f "$_f" ]; then
    echo "FATAL: required file missing: $_f"
    echo "       Negative controls cannot run, so no result from this suite is trustworthy."
    exit 1
  fi
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Harness plumbing
#
# checker_ran() is the guard against a vacuous pass. If the harness ever fails
# to actually invoke the checker -- wrong path, missing copy, non-executable --
# the captured output is empty, and every "output does NOT contain X" assertion
# would pass for the wrong reason. run_checker() refuses to hand back output it
# cannot prove came from a real run. Scenario Z tests this guard itself.
# ---------------------------------------------------------------------------

checker_ran() {
  # checker_ran <output> -> 0 only if the output proves the checker executed
  case "$1" in
    *"Canonical vocab versions"*) return 0 ;;
    *) return 1 ;;
  esac
}

RUN_OUT=""
RUN_RC=0
run_checker() {
  # run_checker <spec_path> [VAR=VAL ...]
  # Sets RUN_OUT and RUN_RC. Counts a failure if the checker did not run.
  _spec="$1"
  shift
  RUN_OUT="$(env "$@" sh "$_spec/scripts/check-downstream-versions.sh" 2>&1)"
  RUN_RC=$?
  if ! checker_ran "$RUN_OUT"; then
    fail "harness invoked the checker at $_spec" \
         "no output banner -- the checker did not run; downstream assertions are void. got: [$RUN_OUT]"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

ALL_REPOS="cascade-cli sdk-typescript sdk-python cascade-agent conformance cascadeprotocol.org cascade-sdk-swift"

mkrepo() {
  # mkrepo <path> <versions-content> -- a local repo with no remote
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

mkclone() {
  # mkclone <bare_path> <work_path> <versions>
  # Builds an upstream bare repo plus a clone of it, so the clone has a real
  # origin/main remote-tracking ref that can be allowed to go stale.
  _bare="$1"; _work="$2"; _c="$3"
  git init --bare -b main "$_bare" >/dev/null 2>&1
  mkrepo "${_bare}.seed" "$_c"
  git -C "${_bare}.seed" remote add origin "$_bare" >/dev/null 2>&1
  git -C "${_bare}.seed" push -q origin main >/dev/null 2>&1
  git clone -q "$_bare" "$_work" >/dev/null 2>&1
}

push_upstream() {
  # push_upstream <bare_path> <versions>
  # Advances the upstream WITHOUT touching any clone, so the clone's
  # origin/main is now behind -- exactly the state of a checkout whose sync
  # merged upstream but which has not fetched since.
  _bare="$1"; _c="$2"
  _tmp="$WORK/push-$$-$(date +%s)"
  rm -rf "$_tmp"
  git clone -q "$_bare" "$_tmp" >/dev/null 2>&1
  printf '%s\n' "$_c" > "$_tmp/VOCAB_VERSIONS"
  git -C "$_tmp" add -A >/dev/null 2>&1
  git -C "$_tmp" -c user.email=t@t -c user.name=t commit -m sync >/dev/null 2>&1
  git -C "$_tmp" push -q origin main >/dev/null 2>&1
  rm -rf "$_tmp"
}

build_dev() {
  # build_dev <name> -> echoes path to a synthetic DEV_ROOT
  _d="$WORK/$1"
  mkdir -p "$_d"
  echo "$_d"
}

mkall() {
  # mkall <dev_root> <versions> -- every downstream repo the checker looks for.
  # Scenarios populate all seven so that a non-zero exit is attributable to the
  # condition under test rather than to repos that merely are not there.
  _d="$1"; _c="$2"
  for _r in $ALL_REPOS; do
    mkrepo "$_d/$_r" "$_c"
  done
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
mkall "$DEV_A" "$VER_MAIN"

install_checker "$DEV_A/spec" "$NEW_SCRIPT"
run_checker "$DEV_A/spec"
OUT_NEW="$RUN_OUT"; RC_NEW="$RUN_RC"

if echo "$OUT_NEW" | grep -q "core = 3.3"; then
  pass "A1 canonical core reads 3.3 from main, not 3.4 from the branch"
else
  fail "A1 canonical core reads 3.3 from main" "got: $(echo "$OUT_NEW" | grep -i 'core =')"
fi

install_checker "$DEV_A/spec" "$BASE_PRE_REF"
run_checker "$DEV_A/spec"
OUT_OLD="$RUN_OUT"
install_checker "$DEV_A/spec" "$NEW_SCRIPT"
if echo "$OUT_OLD" | grep -q "core = 3.4"; then
  pass "A1-NEG pre-fix checker launders the branch (reports canonical core = 3.4)"
else
  fail "A1-NEG pre-fix checker should launder the branch" "specimen did not report 3.4; this control proves nothing"
fi

if echo "$OUT_NEW" | grep -q "NOT YET CANONICAL"; then
  pass "A2 warns loudly that the working tree is ahead of main"
else
  fail "A2 warns loudly that the working tree is ahead of main" "no NOT YET CANONICAL banner"
fi

A3_OK=1
A3_MISS=""
for tok in "feat/health-v2.5" "core: working tree=3.4" "health: working tree=2.5" "clinical: working tree=1.13"; do
  echo "$OUT_NEW" | grep -q "$tok" || { A3_OK=0; A3_MISS="$tok"; }
done
if [ "$A3_OK" = "1" ]; then
  pass "A3 warning names the branch and all three pending vocab bumps"
else
  fail "A3 warning names the branch and all three pending bumps" "missing token: $A3_MISS"
fi

if echo "$OUT_OLD" | grep -q "NOT YET CANONICAL"; then
  fail "A3-NEG pre-fix checker should have no pending-branch warning" "specimen already warned"
else
  pass "A3-NEG pre-fix checker emits no pending-branch warning"
fi

if [ "$RC_NEW" -ne 0 ]; then
  pass "A4 exits non-zero while the spec bump is unmerged (rc=$RC_NEW)"
else
  fail "A4 exits non-zero while the spec bump is unmerged" "rc=0"
fi

if echo "$OUT_NEW" | grep -q "\[cascade-cli\] UP TO DATE"; then
  pass "A5 downstream repo matching main is UP TO DATE (not drifted against a branch)"
else
  fail "A5 downstream repo matching main is UP TO DATE" "got: $(echo "$OUT_NEW" | grep cascade-cli)"
fi

if echo "$OUT_OLD" | grep -q "\[cascade-cli\] DRIFT DETECTED"; then
  pass "A5-NEG pre-fix checker falsely drifts cascade-cli against the branch"
else
  fail "A5-NEG pre-fix checker should falsely drift cascade-cli" "got: $(echo "$OUT_OLD" | grep cascade-cli)"
fi

echo ""
# ===========================================================================
echo "Scenario B: clean main, all seven downstream present and in sync"
# ===========================================================================
DEV_B="$(build_dev devB)"
mkrepo "$DEV_B/spec" "$VER_MAIN"
mkall "$DEV_B" "$VER_MAIN"
install_checker "$DEV_B/spec" "$NEW_SCRIPT"
run_checker "$DEV_B/spec"
OUT_B="$RUN_OUT"; RC_B="$RUN_RC"

if [ "$RC_B" -eq 0 ] && echo "$OUT_B" | grep -q "All downstream repos are in sync"; then
  pass "B1 negative control: a genuinely clean tree exits 0 and reports in sync"
else
  fail "B1 clean tree exits 0" "rc=$RC_B; $(echo "$OUT_B" | tail -4)"
fi

if echo "$OUT_B" | grep -q "NOT YET CANONICAL"; then
  fail "B2 no pending-branch warning when on clean main" "banner appeared on a clean main"
else
  pass "B2 no pending-branch warning when on clean main"
fi

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
mkall "$DEV_C" "$VER_MAIN"
rm -rf "$DEV_C/cascade-cli"
mkrepo "$DEV_C/cascade-cli" "$VER_OLD_DOWNSTREAM"
install_checker "$DEV_C/spec" "$NEW_SCRIPT"
run_checker "$DEV_C/spec"
OUT_C="$RUN_OUT"; RC_C="$RUN_RC"

if [ "$RC_C" -ne 0 ] && echo "$OUT_C" | grep -q "clinical: repo=1.9  spec=1.12"; then
  pass "C1 real downstream drift is still detected, named, and exits non-zero (rc=$RC_C)"
else
  fail "C1 real downstream drift is detected" "rc=$RC_C; $(echo "$OUT_C" | grep clinical)"
fi

if echo "$OUT_C" | grep -q "Action required: update VOCAB_VERSIONS in drifted repos"; then
  pass "C2 drift exit is attributed to drift, not to some other failure"
else
  fail "C2 drift exit names drift as the reason" "$(echo "$OUT_C" | tail -5)"
fi

echo ""
# ===========================================================================
echo "Scenario D: downstream sync exists but is UNMERGED"
# ===========================================================================
DEV_D="$(build_dev devD)"
mkrepo "$DEV_D/spec" "$VER_MAIN"
mkall "$DEV_D" "$VER_MAIN"
rm -rf "$DEV_D/cascade-cli"
mkrepo "$DEV_D/cascade-cli" "$VER_OLD_DOWNSTREAM"
branch_bump "$DEV_D/cascade-cli" "chore/sync-clinical" "$VER_MAIN"
install_checker "$DEV_D/spec" "$NEW_SCRIPT"
run_checker "$DEV_D/spec"
OUT_D="$RUN_OUT"; RC_D="$RUN_RC"

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

install_checker "$DEV_D/spec" "$BASE_PRE_REF"
run_checker "$DEV_D/spec"
OUT_D_OLD="$RUN_OUT"; RC_D_OLD="$RUN_RC"
install_checker "$DEV_D/spec" "$NEW_SCRIPT"
if [ "$RC_D_OLD" -eq 0 ] && echo "$OUT_D_OLD" | grep -q "\[cascade-cli\] UP TO DATE"; then
  pass "D-NEG pre-fix checker calls the unmerged downstream sync UP TO DATE (rc=0)"
else
  fail "D-NEG pre-fix checker should call it UP TO DATE" "rc=$RC_D_OLD; $(echo "$OUT_D_OLD" | grep cascade-cli)"
fi

echo ""
# ===========================================================================
echo "Scenario G: DEFECT 1 -- a stale remote-tracking ref reports false DRIFT"
#
# cascade-cli's sync has merged upstream. The local checkout has not fetched,
# so its origin/main still points at the pre-merge commit. A checker that reads
# that ref without refreshing it reports drift for a repo that is in sync.
# ===========================================================================

build_stale_dev() {
  # Fresh fixture per assertion: reading with fetch enabled updates origin/main
  # as a side effect, so scenarios must not share a clone or they become
  # order-dependent.
  _n="$1"
  _d="$(build_dev "$_n")"
  mkrepo "$_d/spec" "$VER_MAIN"
  mkall "$_d" "$VER_MAIN"
  rm -rf "$_d/cascade-cli"
  mkclone "$WORK/upstream-$_n.git" "$_d/cascade-cli" "$VER_OLD_DOWNSTREAM"
  push_upstream "$WORK/upstream-$_n.git" "$VER_MAIN"
  echo "$_d"
}

DEV_G1="$(build_stale_dev devG1)"
install_checker "$DEV_G1/spec" "$NEW_SCRIPT"
run_checker "$DEV_G1/spec"
OUT_G="$RUN_OUT"; RC_G="$RUN_RC"

if [ "$RC_G" -eq 0 ] && echo "$OUT_G" | grep -q "\[cascade-cli\] UP TO DATE"; then
  pass "G1 refreshes the ref and correctly reports the merged sync as UP TO DATE (rc=0)"
else
  fail "G1 fetches before reading the ref" "rc=$RC_G; $(echo "$OUT_G" | grep cascade-cli)"
fi

DEV_G2="$(build_stale_dev devG2)"
install_checker "$DEV_G2/spec" "$BASE_PRE_FETCH"
run_checker "$DEV_G2/spec"
OUT_G_OLD="$RUN_OUT"; RC_G_OLD="$RUN_RC"

if [ "$RC_G_OLD" -ne 0 ] && echo "$OUT_G_OLD" | grep -q "\[cascade-cli\] DRIFT DETECTED"; then
  pass "G1-NEG pre-fix checker reports false DRIFT from the stale ref (rc=$RC_G_OLD)"
else
  fail "G1-NEG pre-fix checker should report false drift" "rc=$RC_G_OLD; $(echo "$OUT_G_OLD" | grep cascade-cli)"
fi

DEV_G3="$(build_stale_dev devG3)"
install_checker "$DEV_G3/spec" "$NEW_SCRIPT"
run_checker "$DEV_G3/spec" VOCAB_NO_FETCH=1
OUT_G_NF="$RUN_OUT"; RC_G_NF="$RUN_RC"

if [ "$RC_G_NF" -ne 0 ] && echo "$OUT_G_NF" | grep -q "\[cascade-cli\] DRIFT DETECTED"; then
  pass "G2 VOCAB_NO_FETCH=1 reproduces the stale read -- G1 is caused by fetching, nothing else"
else
  fail "G2 VOCAB_NO_FETCH=1 suppresses the fetch" "rc=$RC_G_NF; $(echo "$OUT_G_NF" | grep cascade-cli)"
fi

if echo "$OUT_G_NF" | grep -q "remote-tracking refs were NOT refreshed"; then
  pass "G3 an unfetched run says so, so a green result is never read as verified"
else
  fail "G3 VOCAB_NO_FETCH=1 labels the run" "no unrefreshed-refs notice"
fi

echo ""
# ===========================================================================
echo "Scenario H: DEFECT 1 -- a FAILED fetch must not be reported as UP TO DATE"
# ===========================================================================
DEV_H="$(build_dev devH)"
mkrepo "$DEV_H/spec" "$VER_MAIN"
mkall "$DEV_H" "$VER_MAIN"
rm -rf "$DEV_H/cascade-cli"
mkclone "$WORK/upstream-H.git" "$DEV_H/cascade-cli" "$VER_MAIN"
git -C "$DEV_H/cascade-cli" remote set-url origin "$WORK/no-such-remote.git" >/dev/null 2>&1

install_checker "$DEV_H/spec" "$NEW_SCRIPT"
run_checker "$DEV_H/spec"
OUT_H="$RUN_OUT"; RC_H="$RUN_RC"

if [ "$RC_H" -ne 0 ]; then
  pass "H1 a failed fetch fails the run (rc=$RC_H)"
else
  fail "H1 a failed fetch fails the run" "rc=0 -- an unverifiable repo passed the gate"
fi

if echo "$OUT_H" | grep -q "\[cascade-cli\] UNVERIFIED" && ! echo "$OUT_H" | grep -q "\[cascade-cli\] UP TO DATE"; then
  pass "H2 the verdict is UNVERIFIED, never a plain UP TO DATE off an unrefreshed ref"
else
  fail "H2 verdict is UNVERIFIED" "$(echo "$OUT_H" | grep cascade-cli)"
fi

if echo "$OUT_H" | grep -q "one or more fetches FAILED"; then
  pass "H3 the failure is attributed to the fetch, not silently folded into drift"
else
  fail "H3 fetch failure is named in the summary" "$(echo "$OUT_H" | tail -5)"
fi

install_checker "$DEV_H/spec" "$BASE_PRE_FETCH"
run_checker "$DEV_H/spec"
OUT_H_OLD="$RUN_OUT"; RC_H_OLD="$RUN_RC"

if [ "$RC_H_OLD" -eq 0 ] && echo "$OUT_H_OLD" | grep -q "\[cascade-cli\] UP TO DATE"; then
  pass "H1-NEG pre-fix checker reports UP TO DATE off an unrefreshable ref (rc=0)"
else
  fail "H1-NEG pre-fix checker should report a false all-clear" "rc=$RC_H_OLD; $(echo "$OUT_H_OLD" | grep cascade-cli)"
fi

echo ""
# ===========================================================================
echo "Scenario I: DEFECT 2 -- a repo that is not present must not pass the gate"
# ===========================================================================
DEV_I="$(build_dev devI)"
mkrepo "$DEV_I/spec" "$VER_MAIN"
mkall "$DEV_I" "$VER_MAIN"
rm -rf "$DEV_I/sdk-python"

install_checker "$DEV_I/spec" "$NEW_SCRIPT"
run_checker "$DEV_I/spec"
OUT_I="$RUN_OUT"; RC_I="$RUN_RC"

if [ "$RC_I" -ne 0 ]; then
  pass "I1 a missing downstream repo fails the run (rc=$RC_I)"
else
  fail "I1 a missing downstream repo fails the run" "rc=0 -- an unchecked repo passed the gate"
fi

if echo "$OUT_I" | grep -q "\[sdk-python\] NOT FOUND" && echo "$OUT_I" | grep -q "CANNOT VERIFY"; then
  pass "I2 the missing repo is named and marked as unverifiable"
else
  fail "I2 missing repo is named" "$(echo "$OUT_I" | grep sdk-python)"
fi

if echo "$OUT_I" | grep -q "All downstream repos are in sync"; then
  fail "I3 must not claim everything is in sync while a repo was never read" "the all-clear was printed anyway"
else
  pass "I3 does not claim everything is in sync while a repo was never read"
fi

if echo "$OUT_I" | grep -q "NOT PRESENT and could not be checked"; then
  pass "I4 the summary distinguishes 'not present' from 'drifted'"
else
  fail "I4 summary distinguishes absence from drift" "$(echo "$OUT_I" | tail -6)"
fi

install_checker "$DEV_I/spec" "$BASE_PRE_FETCH"
run_checker "$DEV_I/spec"
OUT_I_OLD="$RUN_OUT"; RC_I_OLD="$RUN_RC"

if [ "$RC_I_OLD" -eq 0 ] && echo "$OUT_I_OLD" | grep -q "All downstream repos are in sync" \
   && echo "$OUT_I_OLD" | grep -q "\[sdk-python\] NOT FOUND"; then
  pass "I1-NEG pre-fix checker prints NOT FOUND and still exits 0 claiming full sync"
else
  fail "I1-NEG pre-fix checker should exit 0 despite the missing repo" "rc=$RC_I_OLD"
fi

echo ""
# ===========================================================================
echo "Scenario J: a successful fetch does not manufacture a false alarm"
# ===========================================================================
DEV_J="$(build_dev devJ)"
mkrepo "$DEV_J/spec" "$VER_MAIN"
mkall "$DEV_J" "$VER_MAIN"
rm -rf "$DEV_J/cascade-cli"
mkclone "$WORK/upstream-J.git" "$DEV_J/cascade-cli" "$VER_MAIN"
install_checker "$DEV_J/spec" "$NEW_SCRIPT"
run_checker "$DEV_J/spec"
OUT_J="$RUN_OUT"; RC_J="$RUN_RC"

if [ "$RC_J" -eq 0 ] && echo "$OUT_J" | grep -q "\[cascade-cli\] UP TO DATE"; then
  pass "J1 negative control: a reachable, already-synced remote still exits 0 (rc=0)"
else
  fail "J1 working remote + in sync exits 0" "rc=$RC_J; $(echo "$OUT_J" | grep cascade-cli)"
fi

if echo "$OUT_J" | grep -q "UNVERIFIED"; then
  fail "J2 a successful fetch must not be marked UNVERIFIED" "$(echo "$OUT_J" | grep UNVERIFIED)"
else
  pass "J2 a successful fetch is not marked UNVERIFIED"
fi

echo ""
# ===========================================================================
echo "Scenario E: escape hatches"
# ===========================================================================
install_checker "$DEV_A/spec" "$NEW_SCRIPT"
run_checker "$DEV_A/spec" VOCAB_ALLOW_WORKTREE=1
OUT_E1="$RUN_OUT"
if echo "$OUT_E1" | grep -q "core = 3.4"; then
  pass "E1 VOCAB_ALLOW_WORKTREE=1 restores working-tree reads for tarball checkouts"
else
  fail "E1 VOCAB_ALLOW_WORKTREE=1 reads the working tree" "$(echo "$OUT_E1" | grep -i 'core =')"
fi

if echo "$OUT_E1" | grep -q "remote-tracking refs were NOT refreshed"; then
  fail "E2 ALLOW_WORKTREE must not emit the unrefreshed-refs notice" "no refs are read in that mode"
else
  pass "E2 ALLOW_WORKTREE does not emit the unrefreshed-refs notice (it reads no refs)"
fi

run_checker "$DEV_A/spec" VOCAB_CANONICAL_REF=feat/health-v2.5
OUT_E3="$RUN_OUT"
if echo "$OUT_E3" | grep -q "core = 3.4" && echo "$OUT_E3" | grep -q "spec @ feat/health-v2.5"; then
  pass "E3 VOCAB_CANONICAL_REF pins an explicit ref and labels the source"
else
  fail "E3 VOCAB_CANONICAL_REF pins an explicit ref" "$(echo "$OUT_E3" | head -4)"
fi

DEV_E="$(build_dev devE)"
mkdir -p "$DEV_E/spec"
printf '%s\n' "$VER_MAIN" > "$DEV_E/spec/VOCAB_VERSIONS"
mkall "$DEV_E" "$VER_MAIN"
install_checker "$DEV_E/spec" "$NEW_SCRIPT"
ERR_E4="$(sh "$DEV_E/spec/scripts/check-downstream-versions.sh" 2>&1 >/dev/null)"
run_checker "$DEV_E/spec"
OUT_E4="$RUN_OUT"
if echo "$ERR_E4" | grep -q "WARNING: canonical versions were read from the spec WORKING TREE" \
   && echo "$OUT_E4" | grep -q "core = 3.3"; then
  pass "E4 non-git checkout falls back to working tree and warns on stderr"
else
  fail "E4 non-git checkout warns on stderr" "stderr: $ERR_E4"
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
# ===========================================================================
echo "Scenario Z: this harness cannot pass vacuously"
#
# Every 'output does NOT contain X' assertion above would pass against empty
# output. These check that a harness which failed to invoke the checker is
# detected rather than silently scoring green.
# ===========================================================================
if checker_ran ""; then
  fail "Z1 empty output must not count as a run" "the guard accepted empty output"
else
  pass "Z1 empty output is not accepted as a run"
fi

if checker_ran "bash: no such file or directory"; then
  fail "Z2 an error message must not count as a run" "the guard accepted an error string"
else
  pass "Z2 a shell error message is not accepted as a run"
fi

DEV_Z="$(build_dev devZ)"
mkdir -p "$DEV_Z/spec/scripts"
Z_OUT="$(sh "$DEV_Z/spec/scripts/check-downstream-versions.sh" 2>&1)"
if checker_ran "$Z_OUT"; then
  fail "Z3 a genuinely absent checker must be detected" "the guard accepted output from a missing script"
else
  pass "Z3 a genuinely absent checker is detected, not scored as a pass"
fi

if checker_ran "$OUT_B"; then
  pass "Z4 distinctness: the guard does accept a real run (it is not constant-false)"
else
  fail "Z4 guard accepts a real run" "the guard rejects genuine output; every assertion above is void"
fi

echo ""
echo "============================================="
TOTAL=$((PASSED + FAILED))
echo "passed=$PASSED  failed=$FAILED  total=$TOTAL"
[ "$FAILED" -eq 0 ] || exit 1
