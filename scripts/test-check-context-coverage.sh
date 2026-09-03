#!/bin/sh
# test-check-context-coverage.sh
#
# Regression suite for scripts/check-context-coverage.py.
#
# The check asserts every record class has a published JSON name. Its failure
# modes are the interesting part: it must catch a class that loses its name, it
# must NOT report the draft vocabularies (which publish no context at all), and
# it must not report a deprecated class. Getting either exclusion wrong makes
# the check permanently red and it gets turned off.
#
# Every case runs against a throwaway copy of the repository.
#
# Usage: ./scripts/test-check-context-coverage.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-context-coverage.py"
PYTHON="${PYTHON:-python3}"

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }

if ! "$PYTHON" -c "import rdflib" 2>/dev/null; then
  echo "ERROR: $PYTHON cannot import rdflib, so this suite would test nothing."
  echo "       Install it:  $PYTHON -m pip install -r scripts/requirements.txt"
  exit 2
fi

scratch() {
  DIR="$(mktemp -d 2>/dev/null || mktemp -d -t ctxcoverage)"
  cp -R "$SPEC_ROOT/ontologies" "$DIR/ontologies"
  cp -R "$SPEC_ROOT/contexts" "$DIR/contexts"
  echo "$DIR"
}

echo ""
echo "=========================================================="
echo "  check-context-coverage.py regression suite"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 1. Green on the repository as it stands, over a non-empty scope.
# ---------------------------------------------------------------------------
echo ""
echo "1. The repository as it stands"

OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" 2>&1)"
if [ $? -eq 0 ]; then
  pass "exits 0 on the real tree"
else
  fail "exits non-zero on the real tree" "$OUT"
fi

SCOPE="$(printf '%s\n' "$OUT" | sed -n 's/^[[:space:]]*in scope:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
if [ -n "$SCOPE" ] && [ "$SCOPE" -gt 0 ]; then
  pass "examined $SCOPE in-scope class(es)"
else
  fail "examined nothing" "The check would pass vacuously. $OUT"
fi

# ---------------------------------------------------------------------------
# 2. THE DEFECT. A record class loses its published name. This is the state
#    twelve classes were in when the check was written (jayostis/spec#50): a
#    consumer either invents a name or cannot address the class.
# ---------------------------------------------------------------------------
echo ""
echo "2. A record class removed from every context"

DIR="$(scratch)"
for f in "$DIR"/contexts/v1/*.jsonld; do
  sed -i.bak '/"coverage:ClaimRecord"/d' "$f"
done
rm -f "$DIR"/contexts/v1/*.bak
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "exits non-zero"
else
  fail "exits 0 with a record class unnamed" "$OUT"
fi
if printf '%s\n' "$OUT" | grep -q "coverage:ClaimRecord"; then
  pass "names coverage:ClaimRecord"
else
  fail "does not name the class it should have caught" "$OUT"
fi
rm -rf "$DIR"

# ---------------------------------------------------------------------------
# 3. THE FIRST EXCLUSION. The five draft vocabularies carry markers and publish
#    no context. If they were in scope every one of their classes would be
#    reported, permanently, and the check would be worthless on day one.
#
#    Asserted by name rather than by count: a draft class is picked and required
#    to be absent from the output while genuinely being marked.
# ---------------------------------------------------------------------------
echo ""
echo "3. Draft-vocabulary classes are out of scope"

OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" 2>&1)"
if printf '%s\n' "$OUT" | grep -qE "diabetes:|genomics:|workbench:|evidence:|advisory:"; then
  fail "a draft-vocabulary class was reported" \
"Those vocabularies publish no context, so every class in them would be
        reported forever. $OUT"
else
  pass "no draft class is reported"
fi

MARKED="$(printf '%s\n' "$OUT" | sed -n 's/^[[:space:]]*marked classes:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
if [ -n "$MARKED" ] && [ -n "$SCOPE" ] && [ "$MARKED" -gt "$SCOPE" ]; then
  pass "scope ($SCOPE) is narrower than the marked set ($MARKED), as intended"
else
  fail "scope is not narrower than the marked set" \
"marked=$MARKED scope=$SCOPE -- the draft exclusion is not doing anything."
fi

# ---------------------------------------------------------------------------
# 4. THE SECOND EXCLUSION. A deprecated class is out of scope. Removing its
#    name would otherwise be impossible without failing this check, which would
#    make retiring a term harder than keeping it.
# ---------------------------------------------------------------------------
echo ""
echo "4. A deprecated class removed from every context is not reported"

DIR="$(scratch)"
for f in "$DIR"/contexts/v1/*.jsonld; do
  sed -i.bak '/"clinical:Allergy"/d' "$f"
done
rm -f "$DIR"/contexts/v1/*.bak
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "exits 0 -- a dead spelling needs no published name"
else
  fail "exits $STATUS after a DEPRECATED class lost its name" "$OUT"
fi
rm -rf "$DIR"

# ---------------------------------------------------------------------------
# 5. A class that gains the marker and no context entry is caught. This is the
#    forward-looking case: the check earns its place on the NEXT record class
#    somebody adds, not on the twelve it was written for.
# ---------------------------------------------------------------------------
echo ""
echo "5. A newly marked class with no context entry is caught"

DIR="$(scratch)"
cat >> "$DIR/ontologies/core/v1/core.ttl" <<'TTL'

cascade:UnnamedProbeRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Unnamed Probe Record"@en .
TTL
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "exits non-zero"
else
  fail "exits 0 with a newly marked class unnamed" "$OUT"
fi
if printf '%s\n' "$OUT" | grep -q "cascade:UnnamedProbeRecord"; then
  pass "names cascade:UnnamedProbeRecord"
else
  fail "does not name the new class" "$OUT"
fi
rm -rf "$DIR"

echo ""
echo "=========================================================="
echo "  passed:  $PASSED"
echo "  failed:  $FAILED"
echo "  total:   $((PASSED + FAILED))"
echo "=========================================================="
echo ""

[ "$FAILED" -eq 0 ] || exit 1
exit 0
