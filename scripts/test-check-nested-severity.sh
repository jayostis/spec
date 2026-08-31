#!/bin/sh
# test-check-nested-severity.sh
#
# Regression suite for check-nested-severity.py.
#
# The defect under test: SHACL defines conformance as an EMPTY validation
# result, and that definition does not consult severity. A constraint expressed
# as "this node conforms to shape S" -- sh:node, sh:qualifiedValueShape -- is
# therefore violated by a nested sh:Warning, and it reports at its OWN severity,
# which is sh:Violation unless declared otherwise. Publishing a Warning on a
# shape that anything reaches by sh:node silently republishes it as a Violation
# on every referring class.
#
# clinical v1.16 did exactly that on clinical:ClinicalDocumentShape, and six
# document subtypes REJECTED status values the release said would only be
# warned about. clinical v1.17 fixed it. This suite proves the check would have
# caught it, by REINTRODUCING the v1.16 authoring into a scratch copy and
# requiring a named failure.
#
# Every assertion is paired with a negative control, and the baseline machinery
# is tested in BOTH directions: a new site must fail, and a baselined site that
# has been fixed must also fail, so the list cannot silently re-absorb a site.
#
# Usage: ./scripts/test-check-nested-severity.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-nested-severity.py"
PYTHON="${PYTHON:-python3}"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }

# A missing parser is a hard failure, never a skip: skipping the suite because
# a dependency is absent reports green while testing nothing.
if ! "$PYTHON" -c "import rdflib" 2>/dev/null; then
  echo "ERROR: $PYTHON cannot import rdflib, so this suite would test nothing."
  echo "       Install it:  $PYTHON -m pip install -r scripts/requirements.txt"
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CLIN="ontologies/clinical/v1/clinical.shapes.ttl"
BASE="scripts/known-severity-escalations.json"

# Build a scratch copy of the shapes tree plus the baseline, which a case may
# mutate freely.
scratch() {
  dir="$WORK/$1"
  mkdir -p "$dir/scripts"
  cp -R "$SPEC_ROOT/ontologies" "$dir/ontologies"
  cp "$SPEC_ROOT/$BASE" "$dir/$BASE"
  echo "$dir"
}

echo ""
echo "=========================================================="
echo "  check-nested-severity.py regression suite"
echo "  spec root: $SPEC_ROOT"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 1. Positive control: the repository as committed must pass.
# ---------------------------------------------------------------------------
echo ""
echo "1. Positive control: the repository's own shapes"

OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "committed shapes satisfy the check (exit 0)"
else
  fail "committed shapes do not pass the check (exit $STATUS)" "$OUT"
fi

if echo "$OUT" | grep -q "RESULT: PASS"; then
  pass "reports RESULT: PASS"
else
  fail "did not report RESULT: PASS" "$OUT"
fi

# ---------------------------------------------------------------------------
# 2. Non-vacuity: the run must actually have examined references.
# ---------------------------------------------------------------------------
echo ""
echo "2. Non-vacuity: the check must examine a non-zero number of references"

SEEN="$(echo "$OUT" | sed -n 's/^  references seen: *\([0-9][0-9]*\).*/\1/p')"
if [ -n "$SEEN" ] && [ "$SEEN" -gt 0 ] 2>/dev/null; then
  pass "examined $SEEN nested-shape reference(s)"
else
  fail "reported no reference count" "$OUT"
fi

# ---------------------------------------------------------------------------
# 3. Negative control: reintroduce the clinical v1.16 authoring.
#
#    Put a sh:Warning property shape back onto clinical:ClinicalDocumentShape,
#    which six subtype shapes reach by sh:node. This is the exact defect the
#    check was written for, and it must name all six referring shapes.
# ---------------------------------------------------------------------------
echo ""
echo "3. Negative control: a sh:Warning back on clinical:ClinicalDocumentShape"

DIR="$(scratch v116)"
awk '
  /^clinical:ClinicalDocumentShape a sh:NodeShape ;/ && !done {
    print
    print "    sh:property ["
    print "        sh:path clinical:status ;"
    print "        sh:in (\"final\") ;"
    print "        sh:severity sh:Warning"
    print "    ] ;"
    done = 1
    next
  }
  { print }
' "$SPEC_ROOT/$CLIN" > "$DIR/$CLIN.tmp"
mv "$DIR/$CLIN.tmp" "$DIR/$CLIN"

BEFORE_W="$(grep -c 'sh:severity sh:Warning' "$SPEC_ROOT/$CLIN")"
AFTER_W="$(grep -c 'sh:severity sh:Warning' "$DIR/$CLIN")"
if [ "$AFTER_W" -eq "$((BEFORE_W + 1))" ]; then
  pass "mutation applied (sh:Warning count $BEFORE_W -> $AFTER_W)"
else
  fail "mutation did not add exactly one sh:Warning" "$BEFORE_W -> $AFTER_W"
fi

OUT_V="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_V=$?
if [ $STATUS_V -ne 0 ]; then
  pass "check fails against the reintroduced defect (exit $STATUS_V)"
else
  fail "check PASSED against the clinical v1.16 defect" "$OUT_V"
fi

MISSING=""
for SHAPE in ProgressNoteShape DischargeSummaryShape ConsultationNoteShape \
             LaboratoryReportShape ImagingReportShape VisitSummaryShape; do
  echo "$OUT_V" | grep -q "clinical:$SHAPE sh:node clinical:ClinicalDocumentShape" || \
    MISSING="$MISSING $SHAPE"
done
if [ -z "$MISSING" ]; then
  pass "names all six referring document shapes"
else
  fail "did not name every referring shape" "missing:$MISSING"
fi

if echo "$OUT_V" | grep -q "unbaselined site"; then
  pass "reports the sites as unbaselined"
else
  fail "did not report unbaselined sites" "$OUT_V"
fi

# ---------------------------------------------------------------------------
# 4. Negative control: an sh:Info escalates exactly as an sh:Warning does.
#
#    Severity is not a spectrum here. Anything short of sh:Violation makes the
#    referenced shape non-conforming, so Info must be caught too.
# ---------------------------------------------------------------------------
echo ""
echo "4. Negative control: sh:Info on a referenced shape is caught as well"

DIR="$(scratch info)"
awk '
  /^clinical:ClinicalDocumentShape a sh:NodeShape ;/ && !done {
    print
    print "    sh:property ["
    print "        sh:path clinical:displayName ;"
    print "        sh:minCount 1 ;"
    print "        sh:severity sh:Info"
    print "    ] ;"
    done = 1
    next
  }
  { print }
' "$SPEC_ROOT/$CLIN" > "$DIR/$CLIN.tmp"
mv "$DIR/$CLIN.tmp" "$DIR/$CLIN"

OUT_I="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_I=$?
if [ $STATUS_I -ne 0 ]; then
  pass "check fails on a nested sh:Info (exit $STATUS_I)"
else
  fail "check PASSED on a nested sh:Info" "$OUT_I"
fi

if echo "$OUT_I" | grep -q "sh:Info"; then
  pass "names sh:Info as the severity carried"
else
  fail "did not name sh:Info" "$OUT_I"
fi

# ---------------------------------------------------------------------------
# 5. Negative control: declaring sh:severity on the REFERENCE is not a cure.
#
#    The tempting non-fix. It demotes the whole referenced shape rather than
#    the one nested result, so the check must still report the site.
# ---------------------------------------------------------------------------
echo ""
echo "5. Negative control: sh:severity beside the sh:node does not silence it"

DIR="$(scratch sev)"
awk '
  /^clinical:ClinicalDocumentShape a sh:NodeShape ;/ && !done {
    print
    print "    sh:property ["
    print "        sh:path clinical:status ;"
    print "        sh:in (\"final\") ;"
    print "        sh:severity sh:Warning"
    print "    ] ;"
    done = 1
    next
  }
  /sh:node clinical:ClinicalDocumentShape ;/ {
    print "    sh:severity sh:Warning ;"
    print
    next
  }
  { print }
' "$SPEC_ROOT/$CLIN" > "$DIR/$CLIN.tmp"
mv "$DIR/$CLIN.tmp" "$DIR/$CLIN"

OUT_S="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_S=$?
if [ $STATUS_S -ne 0 ]; then
  pass "check still fails when the reference declares its own severity (exit $STATUS_S)"
else
  fail "sh:severity on the reference silenced the check" "$OUT_S"
fi

# ---------------------------------------------------------------------------
# 6. Baseline direction control: a FIXED baselined site must also fail.
#
#    The list can only shrink deliberately. A site that stops occurring while
#    its entry remains is a stale baseline, and a stale baseline can silently
#    re-absorb the site later.
# ---------------------------------------------------------------------------
echo ""
echo "6. Baseline control: a baselined site that no longer occurs must fail"

DIR="$(scratch stale)"
"$PYTHON" - "$DIR/$BASE" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path))
doc["entries"].append({
    "site": "example:NoSuchShape sh:node example:AlsoNoSuchShape",
    "ownedBy": "test",
    "detail": "Site that does not exist; the check must report it as stale.",
})
json.dump(doc, open(path, "w"), indent=2)
PY

OUT_B="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_B=$?
if [ $STATUS_B -ne 0 ]; then
  pass "check fails on a stale baseline entry (exit $STATUS_B)"
else
  fail "check PASSED with a baseline entry naming a site that does not occur" "$OUT_B"
fi

if echo "$OUT_B" | grep -q "no longer present"; then
  pass "reports the entry as no longer present"
else
  fail "did not report the stale entry" "$OUT_B"
fi

# ---------------------------------------------------------------------------
# 7. Emptiness control: a corpus with no nested-shape reference proves nothing.
# ---------------------------------------------------------------------------
echo ""
echo "7. Emptiness control: a corpus with no sh:node reference at all"

DIR="$WORK/empty"
mkdir -p "$DIR/ontologies/example/v1" "$DIR/scripts"
cat > "$DIR/ontologies/example/v1/example.shapes.ttl" <<'TTL'
@prefix ex:  <https://ns.cascadeprotocol.org/example/v1#> .
@prefix sh:  <http://www.w3.org/ns/shacl#> .
ex:AlphaShape a sh:NodeShape ;
    sh:targetClass ex:Alpha ;
    sh:property [ sh:path ex:name ; sh:minCount 1 ] .
TTL
cat > "$DIR/$BASE" <<'JSON'
{ "entries": [] }
JSON

OUT_E="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_E=$?
if [ $STATUS_E -ne 0 ]; then
  pass "check fails when it examined no reference (exit $STATUS_E)"
else
  fail "check PASSED while examining zero references" "$OUT_E"
fi

if echo "$OUT_E" | grep -q "^EMPTY"; then
  pass "reports EMPTY rather than PASS"
else
  fail "did not report EMPTY" "$OUT_E"
fi

# ---------------------------------------------------------------------------
# 8. Missing-baseline control: the baseline is a required input.
# ---------------------------------------------------------------------------
echo ""
echo "8. Missing-baseline control: an absent baseline must error, not pass"

DIR="$WORK/nobaseline"
mkdir -p "$DIR"
cp -R "$SPEC_ROOT/ontologies" "$DIR/ontologies"
OUT_M="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_M=$?
if [ $STATUS_M -ne 0 ]; then
  pass "check errors when the baseline is absent (exit $STATUS_M)"
else
  fail "check PASSED with no baseline present" "$OUT_M"
fi

# ---------------------------------------------------------------------------
# 9. Missing-corpus control: a root with no shapes must error, not pass.
# ---------------------------------------------------------------------------
echo ""
echo "9. Missing-corpus control: an empty root must error, not pass"

DIR="$WORK/nothing"
mkdir -p "$DIR"
OUT_N="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_N=$?
if [ $STATUS_N -ne 0 ]; then
  pass "check errors on a root containing no shapes (exit $STATUS_N)"
else
  fail "check PASSED on a root containing no shapes" "$OUT_N"
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
