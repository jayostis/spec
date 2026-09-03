#!/bin/sh
# test-check-context-validity.sh
#
# Regression suite for check-context-validity.py.
#
# The defect under test: a section-header comment written as an ordinary context
# term -- "__comment_core": "=== Core Vocabulary ===" -- is not a comment. Every
# non-keyword key in a context IS a term definition, so its value must be an
# IRI, and prose is not one. A conformant processor rejects the entire file over
# it. Three of the seven published contexts shipped that way. See issue #48.
#
# Every assertion below is paired with a NEGATIVE CONTROL: a scratch copy of a
# real context with one defect deliberately introduced, which the check must
# catch and must name. A check that has only ever been observed passing is not
# evidence that it can fail -- and a validity check that cannot fail would be
# this same defect one level up.
#
# Control 6 is the one to read before changing the dependency. rdflib is already
# pinned for this repository's other checks and it parses JSON-LD, so it is the
# obvious thing to reach for and it is the wrong thing: it accepts the broken
# file. That control fails if anyone swaps the strict processor out for it.
#
# Usage: ./scripts/test-check-context-validity.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-context-validity.py"
PYTHON="${PYTHON:-python3}"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }

# A missing processor is a hard failure, never a skip. Skipping the suite
# because a dependency is absent reports green while testing nothing, which is
# the exact class of defect this file guards against.
if ! "$PYTHON" -c "import pyld" 2>/dev/null; then
  echo "ERROR: $PYTHON cannot import pyld, so this suite would test nothing."
  echo "       Install it:  $PYTHON -m pip install -r scripts/requirements.txt"
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# coverage.jsonld is the smallest context that loads cleanly today, so a
# failure in a control below is the injected defect and not pre-existing noise.
SUBJECT="$SPEC_ROOT/contexts/v1/coverage.jsonld"

# inject <src> <dst> <key> <value> -- add one term to a context's @context.
inject() {
  "$PYTHON" - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
src, dst, key, value = sys.argv[1:5]
with open(src, encoding="utf-8") as fh:
    doc = json.load(fh)
assert key not in doc["@context"], "fixture already defines %r" % key
doc["@context"][key] = value
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
PY
}

echo "check-context-validity.py regression suite"
echo ""

# -- 1. The repository itself passes -----------------------------------------
# The outer loop. Red until the eight prose terms are gone from contexts/v1/.
if (cd "$SPEC_ROOT" && "$PYTHON" "$CHECK" >/dev/null 2>&1); then
  pass "every context in this repository loads in a strict processor"
else
  (cd "$SPEC_ROOT" && "$PYTHON" "$CHECK" 2>&1 | tail -20)
  fail "every context in this repository loads in a strict processor" \
       "the check reports a problem against unmodified sources"
fi

# -- 2. Negative control: a prose-valued term --------------------------------
# The exact defect that shipped, in the exact spelling it shipped in.
inject "$SUBJECT" "$WORK/prose.jsonld" "__comment_section" "=== Section ==="
OUT="$("$PYTHON" "$CHECK" "$WORK/prose.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "INVALID TERM '__comment_section'"; then
  pass "a term whose value is prose is caught and named"
else
  fail "a term whose value is prose is caught and named" \
       "check did not fail, or did not name the term: $OUT"
fi

# -- 3. Negative control: an @-prefixed key is not automatically ignored ------
# A processor ignores an @-prefixed key only when what follows the @ is LETTERS
# ONLY. "@comment_core" is the obvious way to rescue the old names and it fails
# exactly as the original did, which is why deletion was chosen over re-keying.
inject "$SUBJECT" "$WORK/atunderscore.jsonld" "@comment_section" "=== Section ==="
OUT="$("$PYTHON" "$CHECK" "$WORK/atunderscore.jsonld" 2>&1)"
if [ $? -ne 0 ]; then
  pass "an @-key with an underscore is still rejected"
else
  fail "an @-key with an underscore is still rejected" \
       "check passed a context a processor refuses: $OUT"
fi

# -- 4. Positive control: a letters-only @-key IS ignored ---------------------
# The other half of control 3. Without this the suite would be satisfied by a
# check that simply rejected every @-prefixed key.
inject "$SUBJECT" "$WORK/atletters.jsonld" "@commentSection" "=== Section ==="
OUT="$("$PYTHON" "$CHECK" "$WORK/atletters.jsonld" 2>&1)"
if [ $? -eq 0 ]; then
  pass "a letters-only @-key is ignored by the processor and passes"
else
  fail "a letters-only @-key is ignored by the processor and passes" \
       "check rejected a context a processor accepts: $OUT"
fi

# -- 5. Non-vacuity: nothing to check must not read as success ----------------
cat > "$WORK/empty.jsonld" <<'JSON'
{ "@context": {} }
JSON
OUT="$("$PYTHON" "$CHECK" "$WORK/empty.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "EMPTY"; then
  pass "a context defining no terms is reported as examining nothing"
else
  fail "a context defining no terms is reported as examining nothing" \
       "expected a failure naming EMPTY: $OUT"
fi

# -- 6. The processor must be a strict one -----------------------------------
# rdflib parses JSON-LD and accepts the broken file. If this check is ever
# rewritten against it -- the tempting move, since rdflib is already pinned --
# every control above still passes except this one.
if "$PYTHON" -c "import rdflib" 2>/dev/null; then
  LENIENT="$("$PYTHON" - "$WORK/prose.jsonld" <<'PY'
import json, sys
from rdflib import Graph
with open(sys.argv[1], encoding="utf-8") as fh:
    ctx = json.load(fh)["@context"]
doc = json.dumps({"@context": ctx, "@id": "urn:x", "coverageType": "v"})
try:
    Graph().parse(data=doc, format="json-ld")
    print("accepted")
except Exception:
    print("rejected")
PY
)"
  if [ "$LENIENT" = "accepted" ]; then
    pass "rdflib accepts the broken context, so the check is not using it"
  else
    fail "rdflib accepts the broken context, so the check is not using it" \
         "rdflib rejected it too, so control 6 no longer distinguishes anything"
  fi
else
  fail "rdflib accepts the broken context, so the check is not using it" \
       "rdflib is not importable, so this control tested nothing"
fi

echo ""
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
