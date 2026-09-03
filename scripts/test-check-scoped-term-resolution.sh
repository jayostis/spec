#!/bin/sh
# test-check-scoped-term-resolution.sh
#
# Regression suite for check-scoped-term-resolution.py.
#
# The defect class under test: check-context-validity.py proves a context
# LOADS; it says nothing about whether a term resolves to the right IRI.
# Term-scoped `@context` and `@vocab` (#47, #44) are new constructs in this
# repository and easy to write in a shape that parses cleanly but resolves
# wrong -- the base rate for that here is not zero, see CLAUDE.md.
#
# Each assertion below is paired with a NEGATIVE CONTROL: a scratch copy of
# the real contexts with the fix for one term deliberately reverted to its
# pre-#47/#44 form, which the check must fail. A check only ever observed
# passing is not evidence it can fail.
#
# Usage: ./scripts/test-check-scoped-term-resolution.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-scoped-term-resolution.py"
PYTHON="${PYTHON:-python3}"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }

if ! "$PYTHON" -c "import pyld" 2>/dev/null; then
  echo "ERROR: $PYTHON cannot import pyld, so this suite would test nothing."
  echo "       Install it:  $PYTHON -m pip install -r scripts/requirements.txt"
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The check reads contexts/v1/*.jsonld relative to the CWD it is run from, so
# every control below runs with CWD set to a scratch copy of the real tree --
# never the real one -- and copies the checker script alongside it.
seed_scratch() {
  rm -rf "$WORK/scratch"
  mkdir -p "$WORK/scratch/contexts/v1" "$WORK/scratch/scripts"
  cp "$SPEC_ROOT/contexts/v1"/*.jsonld "$WORK/scratch/contexts/v1/"
  cp "$CHECK" "$WORK/scratch/scripts/"
}

echo "check-scoped-term-resolution.py regression suite"
echo

# --- 1. The real, fixed files pass. ------------------------------------
seed_scratch
if (cd "$WORK/scratch" && "$PYTHON" scripts/check-scoped-term-resolution.py >"$WORK/out.log" 2>&1); then
  pass "the fixed contexts pass every resolution check"
else
  fail "the fixed contexts pass every resolution check" \
       "expected exit 0; check ran against a scratch copy seeded from $SPEC_ROOT/contexts/v1"
fi

# --- 2. Negative control: dataProvenance reverted to @type: @id. --------
seed_scratch
"$PYTHON" - "$WORK/scratch/contexts/v1/core.jsonld" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    doc = json.load(fh)
term = doc["@context"]["dataProvenance"]
term["@type"] = "@id"           # the pre-#47 (buggy) form
del term["@context"]            # the @vocab fallback that made @vocab relevant
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
if (cd "$WORK/scratch" && "$PYTHON" scripts/check-scoped-term-resolution.py >"$WORK/out.log" 2>&1); then
  fail "dataProvenance reverted to @type: @id is caught" \
       "check exited 0 against a context with the pre-#47 form; it should have failed"
else
  if grep -q "dataProvenance" "$WORK/out.log"; then
    pass "dataProvenance reverted to @type: @id is caught, and named"
  else
    fail "dataProvenance reverted to @type: @id is caught, and named" \
         "check failed (good) but did not name dataProvenance in its output"
  fi
fi

# --- 3. Negative control: clinicalSummary loses its scoped @context. ----
seed_scratch
"$PYTHON" - "$WORK/scratch/contexts/v1/core.jsonld" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    doc = json.load(fh)
term = doc["@context"]["clinicalSummary"]
del term["@context"]            # the pre-#44 (buggy) form: no scoped children
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
if (cd "$WORK/scratch" && "$PYTHON" scripts/check-scoped-term-resolution.py >"$WORK/out.log" 2>&1); then
  fail "clinicalSummary losing its scoped context is caught" \
       "check exited 0 against a context with the pre-#44 form; it should have failed"
else
  if grep -q "clinicalSummary" "$WORK/out.log"; then
    pass "clinicalSummary losing its scoped context is caught, and named"
  else
    fail "clinicalSummary losing its scoped context is caught, and named" \
         "check failed (good) but did not name clinicalSummary in its output"
  fi
fi

# --- 4. Negative control: a flat term is accidentally moved. ------------
seed_scratch
"$PYTHON" - "$WORK/scratch/contexts/v1/health.jsonld" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    doc = json.load(fh)
doc["@context"]["vaccineName"] = "health:vaccineNameRenamed"   # simulate drift
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2)
PYEOF
if (cd "$WORK/scratch" && "$PYTHON" scripts/check-scoped-term-resolution.py >"$WORK/out.log" 2>&1); then
  fail "an unrelated flat term moving is caught (regression guard)" \
       "check exited 0 after vaccineName's predicate changed; it should have failed"
else
  pass "an unrelated flat term moving is caught (regression guard)"
fi

# --- 5. A missing PyLD must exit non-zero, never a traceback swallowed. -
# Matches check-context-validity.py's equivalent control: verify the guard
# text is present rather than spawning a second interpreter with pyld hidden,
# which is not portably achievable across sh implementations.
if grep -q "cannot import pyld, so nothing would be checked" "$CHECK"; then
  pass "a missing pyld is guarded with a message, not a bare traceback (static check)"
else
  fail "a missing pyld is guarded with a message, not a bare traceback (static check)" \
       "expected guard text not found in $CHECK"
fi

echo
echo "=========================================================="
echo "  passed: $PASSED   failed: $FAILED"
echo "=========================================================="

[ "$FAILED" -eq 0 ]
