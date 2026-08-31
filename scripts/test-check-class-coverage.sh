#!/bin/sh
# test-check-class-coverage.sh
#
# Regression suite for check-class-coverage.py.
#
# The defect under test: a class declaring rdfs:subClassOf prov:Entity or
# prov:Activity holds record data, but if no shape names it in sh:targetClass
# then SHACL reports conforms:true over its records having examined nothing.
# That verdict is indistinguishable from one earned by satisfying every
# constraint, and check-shape-targets.py reports PASS 3/3 straight over it,
# because its T assertion fires only for a superclass some shape already
# targets and nothing targets prov:Entity.
#
# clinical:CoverageRecord lived its whole life that way. clinical v1.18 shaped
# it, so this suite cannot assert the live defect directly -- instead case 3
# REMOVES clinical:CoverageRecordShape from a scratch copy and requires the
# check to name the class, which is what proves it would have caught it.
#
# Every assertion is paired with a negative control, and the baseline machinery
# is tested in BOTH directions: a newly unshaped class must fail, and a
# baselined class that has been shaped must also fail, so the list cannot
# silently re-absorb a class.
#
# Usage: ./scripts/test-check-class-coverage.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-class-coverage.py"
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

CLIN_SHAPES="ontologies/clinical/v1/clinical.shapes.ttl"
CLIN_TTL="ontologies/clinical/v1/clinical.ttl"
BASE="scripts/class-coverage-baseline.json"

# Build a scratch copy of the ontology tree plus the baseline, which a case may
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
echo "  check-class-coverage.py regression suite"
echo "  spec root: $SPEC_ROOT"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 1. Positive control: the repository as committed must pass.
# ---------------------------------------------------------------------------
echo ""
echo "1. Positive control: the repository's own ontologies"

OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "committed ontologies satisfy the check (exit 0)"
else
  fail "committed ontologies do not pass the check (exit $STATUS)" "$OUT"
fi

# ---------------------------------------------------------------------------
# 2. --no-baseline reports the real gap rather than hiding it.
# ---------------------------------------------------------------------------
echo ""
echo "2. --no-baseline exposes the unshaped classes"

OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" --no-baseline 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "exits non-zero with the baseline ignored (exit $STATUS)"
else
  fail "PASSED with the baseline ignored, so nothing is unshaped" "$OUT"
fi
if echo "$OUT" | grep -q "diabetes:GlucoseReading"; then
  pass "names a known unshaped class (diabetes:GlucoseReading)"
else
  fail "did not name diabetes:GlucoseReading" "$OUT"
fi

# ---------------------------------------------------------------------------
# 3. THE DEFINING CASE. Remove the shape clinical v1.18 added and require the
#    check to report the class it was written for. This is the only assertion
#    that proves the check would have caught the live defect.
# ---------------------------------------------------------------------------
echo ""
echo "3. Reintroduce the pre-v1.18 state: clinical:CoverageRecord unshaped"

DIR="$(scratch pre-v118)"
# Delete the shape block: from its subject line to the terminating period that
# closes the node shape, which is the line consisting of "    ] ." at its end.
"$PYTHON" - "$DIR/$CLIN_SHAPES" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
start = text.index("clinical:CoverageRecordShape a sh:NodeShape")
end = text.index("\n\n", text.index("sh:message \"Schema version must be in format major.minor\"@en\n    ] .", start))
open(path, "w", encoding="utf-8").write(text[:start] + text[end:])
PY

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "unshaped clinical:CoverageRecord fails the check (exit $STATUS)"
else
  fail "clinical:CoverageRecord unshaped and the check PASSED" "$OUT"
fi
if echo "$OUT" | grep -q "clinical:CoverageRecord"; then
  pass "names clinical:CoverageRecord"
else
  fail "failed without naming clinical:CoverageRecord" "$OUT"
fi

# Negative control for case 3: with the shape restored the same tree passes, so
# the failure above is attributable to the deletion and to nothing else.
DIR="$(scratch pre-v118-control)"
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "negative control: the same tree with the shape intact passes"
else
  fail "negative control failed, so case 3 proves nothing" "$OUT"
fi

# ---------------------------------------------------------------------------
# 4. A newly unshaped class is caught WITH the baseline present. This is the
#    regression the whole check exists to prevent.
# ---------------------------------------------------------------------------
echo ""
echo "4. A new prov-rooted class with no shape, baseline present"

DIR="$(scratch new-class)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchTestRecord a owl:Class ;
    rdfs:label "Scratch Test Record"@en ;
    rdfs:subClassOf prov:Entity .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "a new unshaped class fails despite the baseline (exit $STATUS)"
else
  fail "a new unshaped class PASSED, so the baseline is a mute switch" "$OUT"
fi
if echo "$OUT" | grep -q "clinical:ScratchTestRecord"; then
  pass "names clinical:ScratchTestRecord"
else
  fail "failed without naming the new class" "$OUT"
fi

# ---------------------------------------------------------------------------
# 5. Negative control for case 4: the same class WITH a shape must pass, so the
#    failure above is the missing shape and not merely the new class.
# ---------------------------------------------------------------------------
echo ""
echo "5. Negative control: the same new class, shaped"

DIR="$(scratch new-class-shaped)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchTestRecord a owl:Class ;
    rdfs:label "Scratch Test Record"@en ;
    rdfs:subClassOf prov:Entity .
EOF
cat >> "$DIR/$CLIN_SHAPES" <<'EOF'

clinical:ScratchTestRecordShape a sh:NodeShape ;
    sh:targetClass clinical:ScratchTestRecord ;
    rdfs:label "Scratch Test Record Shape"@en .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "a new class with a shape passes (exit 0)"
else
  fail "a new class with a shape still failed" "$OUT"
fi

# ---------------------------------------------------------------------------
# 6. Baseline ratchet, downward direction: removing an entry re-fails, naming
#    the class. This is what makes the list a record rather than a filter.
# ---------------------------------------------------------------------------
echo ""
echo "6. Baseline ratchet: removing an entry re-fails"

DIR="$(scratch drop-entry)"
"$PYTHON" - "$DIR/$BASE" <<'PY'
import json, sys
path = sys.argv[1]
doc = json.load(open(path, encoding="utf-8"))
doc["entries"] = [e for e in doc["entries"] if e["class"] != "coverage:DenialNotice"]
json.dump(doc, open(path, "w", encoding="utf-8"), indent=2)
PY

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "a de-baselined unshaped class fails (exit $STATUS)"
else
  fail "removing a baseline entry did not re-fail the check" "$OUT"
fi
if echo "$OUT" | grep -q "coverage:DenialNotice"; then
  pass "names coverage:DenialNotice"
else
  fail "failed without naming coverage:DenialNotice" "$OUT"
fi

# ---------------------------------------------------------------------------
# 7. Baseline ratchet, upward direction: a baselined class that HAS been shaped
#    must also fail, so a fixed class cannot be silently re-absorbed later.
# ---------------------------------------------------------------------------
echo ""
echo "7. Baseline ratchet: a baselined class that is now shaped must fail"

DIR="$(scratch stale-entry)"
cat >> "$DIR/$CLIN_SHAPES" <<'EOF'

clinical:ImagingStudyShape a sh:NodeShape ;
    sh:targetClass clinical:ImagingStudy ;
    rdfs:label "Imaging Study Shape"@en .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "a stale baseline entry fails (exit $STATUS)"
else
  fail "a baselined class that is now shaped did not fail the check" "$OUT"
fi
if echo "$OUT" | grep -q "clinical:ImagingStudy"; then
  pass "names clinical:ImagingStudy as no longer unshaped"
else
  fail "failed without naming clinical:ImagingStudy" "$OUT"
fi

# ---------------------------------------------------------------------------
# 8. A class with NO rdfs:subClassOf is out of scope and must not be reported.
#    This is the scope boundary the issue drew deliberately: that population
#    mixes value enumerations with record classes and separating them is a
#    vocabulary judgement, not a check's.
# ---------------------------------------------------------------------------
echo ""
echo "8. Scope boundary: a class with no PROV superclass is not reported"

DIR="$(scratch no-superclass)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchRootlessClass a owl:Class ;
    rdfs:label "Scratch Rootless Class"@en .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "a class with no PROV superclass is out of scope (exit 0)"
else
  fail "a class with no PROV superclass was reported" "$OUT"
fi

# ---------------------------------------------------------------------------
# 9. Missing-baseline control: absent baseline must error, not pass.
# ---------------------------------------------------------------------------
echo ""
echo "9. Missing-baseline control"

DIR="$(scratch no-baseline)"
rm -f "$DIR/$BASE"
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "check errors when the baseline is absent (exit $STATUS)"
else
  fail "check PASSED with no baseline present" "$OUT"
fi

# ---------------------------------------------------------------------------
# 10. Missing-corpus control: a root with no ontologies must error, not pass.
# ---------------------------------------------------------------------------
echo ""
echo "10. Missing-corpus control: an empty root must error, not pass"

DIR="$WORK/nothing"
mkdir -p "$DIR"
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "check errors on a root containing no ontologies (exit $STATUS)"
else
  fail "check PASSED on a root containing no ontologies" "$OUT"
fi

# ---------------------------------------------------------------------------
# 11. Missing-shapes control: ontologies present but no shapes at all. Every
#     class would look unshaped, so a PASS here would be meaningless and an
#     ordinary FAIL would be indistinguishable from a real finding.
# ---------------------------------------------------------------------------
echo ""
echo "11. Missing-shapes control: ontologies with no shapes must error"

DIR="$(scratch no-shapes)"
find "$DIR/ontologies" -name '*.shapes.ttl' -delete
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -eq 2 ]; then
  pass "check errors (exit 2) on a root with ontologies but no shapes"
else
  fail "expected exit 2 on a root with no shapes, got $STATUS" "$OUT"
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
