#!/bin/sh
# test-check-record-class-registry.sh
#
# Regression suite for scripts/check-record-class-registry.py.
#
# The check compares two independently maintained enumerations of the same
# fact -- pod-structure.md's solid:forClass registrations and the ontologies'
# cascade:RecordClass markers -- so its whole value is that it FAILS when they
# drift. A comparison that cannot report a difference is decoration.
#
# Every case runs against a throwaway copy of the repository. Nothing here
# writes to the working tree.
#
# Usage: ./scripts/test-check-record-class-registry.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-record-class-registry.py"
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

# A scratch copy carrying only what the check reads.
scratch() {
  DIR="$(mktemp -d 2>/dev/null || mktemp -d -t rcregistry)"
  cp -R "$SPEC_ROOT/ontologies" "$DIR/ontologies"
  cp "$SPEC_ROOT/pod-structure.md" "$DIR/pod-structure.md"
  echo "$DIR"
}

echo ""
echo "=========================================================="
echo "  check-record-class-registry.py regression suite"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 1. Green on the repository as it stands. Every later case breaks something
#    specific, so this is what says the breakage caused the failure.
# ---------------------------------------------------------------------------
echo ""
echo "1. The repository as it stands"

OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" 2>&1)"
if [ $? -eq 0 ]; then
  pass "exits 0 on the real tree"
else
  fail "exits non-zero on the real tree" "$OUT"
fi

REG="$(printf '%s\n' "$OUT" | sed -n 's/^[[:space:]]*registrations:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
if [ -n "$REG" ] && [ "$REG" -gt 0 ]; then
  pass "found $REG registration(s) to compare"
else
  fail "found no registrations" "The check would pass vacuously. $OUT"
fi

# ---------------------------------------------------------------------------
# 2. THE DEFECT. A registered class loses its marker: the ontology stops saying
#    a Pod stores it while pod-structure.md still registers a path for it.
#    This is the silent-omission failure mode an explicit list has, and the
#    only reason this check exists.
# ---------------------------------------------------------------------------
echo ""
echo "2. A registered class with its marker removed"

DIR="$(scratch)"
sed -i.bak 's/^health:LabResultRecord a owl:Class, cascade:RecordClass ;/health:LabResultRecord a owl:Class ;/' \
  "$DIR/ontologies/health/v1/health.ttl"
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "exits non-zero"
else
  fail "exits 0 with a registered class unmarked" "$OUT"
fi
if printf '%s\n' "$OUT" | grep -q "health:LabResultRecord"; then
  pass "names health:LabResultRecord"
else
  fail "does not name the class it should have caught" "$OUT"
fi
rm -rf "$DIR"

# ---------------------------------------------------------------------------
# 3. The other direction of drift: a registration is added for a class nobody
#    marked. Same finding, different cause -- somebody laid out a pod path
#    without declaring the class stores records.
# ---------------------------------------------------------------------------
echo ""
echo "3. A registration added for an unmarked class"

DIR="$(scratch)"
cat >> "$DIR/pod-structure.md" <<'MD'

    <#probe>
        a solid:TypeRegistration ;
        solid:forClass cascade:DataProvenance ;
        solid:instanceContainer </clinical/probe.ttl> .
MD
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "exits non-zero"
else
  fail "exits 0 with an unmarked class registered" "$OUT"
fi
if printf '%s\n' "$OUT" | grep -q "cascade:DataProvenance"; then
  pass "names cascade:DataProvenance"
else
  fail "does not name the newly registered class" "$OUT"
fi
rm -rf "$DIR"

# ---------------------------------------------------------------------------
# 4. NO MATERIAL IS A FAILURE, NOT A PASS. If pod-structure.md stops carrying
#    registrations -- a rewrite, a moved section, a regex that stops matching --
#    the comparison has nothing to compare and must say so. Reporting PASS over
#    an empty input is how a check dies without anyone noticing.
# ---------------------------------------------------------------------------
echo ""
echo "4. A pod-structure.md with no registrations"

DIR="$(scratch)"
printf '# Pod Structure\n\nNo registrations here.\n' > "$DIR/pod-structure.md"
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
if [ $? -ne 0 ]; then
  pass "exits non-zero rather than passing vacuously"
else
  fail "exits 0 with nothing to compare" "$OUT"
fi
rm -rf "$DIR"

# ---------------------------------------------------------------------------
# 5. The documented TEMPLATE is not a registration. pod-structure.md's
#    registration-format section shows `solid:forClass {vocabulary}:{ClassName}`,
#    which names no class. A regex that matched it would report a permanent
#    unfixable finding and the check would be turned off.
# ---------------------------------------------------------------------------
echo ""
echo "5. The {vocabulary}:{ClassName} template is not treated as a registration"

DIR="$(scratch)"
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
if printf '%s\n' "$OUT" | grep -q "{vocabulary}"; then
  fail "the template placeholder was read as a registration" "$OUT"
else
  pass "the placeholder is ignored"
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
