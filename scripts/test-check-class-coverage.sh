#!/bin/sh
# test-check-class-coverage.sh
#
# Regression suite for check-class-coverage.py.
#
# The defect under test: a class carrying `a cascade:RecordClass` holds record
# data, but if no shape names it in sh:targetClass then SHACL reports
# conforms:true over its records having examined nothing. That verdict is
# indistinguishable from one earned by satisfying every constraint, and
# check-shape-targets.py reports PASS 3/3 straight over it, because its T
# assertion fires only for a superclass some shape already targets.
#
# The marker replaced a reading of rdfs:subClassOf prov:Entity in core v3.13
# (jayostis/spec#34, #50). Case 13 asserts the consequence that is easiest to
# undo by accident: membership is not inherited.
#
# clinical:CoverageRecord lived its whole life that way. clinical v1.18 shaped
# it, so this suite cannot assert the live defect directly -- instead case 3
# REMOVES every shape targeting the class from a scratch copy and requires the
# check to name it, which is what proves it would have caught it.
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
BASE="scripts/known-unshaped-classes.json"

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
# 3. THE DEFINING CASE. Remove every shape clinical v1.18 and v1.19 added and
#    require the check to report the class they were written for. This is the
#    only assertion that proves the check would have caught the live defect.
# ---------------------------------------------------------------------------
echo ""
echo "3. Reintroduce the pre-v1.18 state: clinical:CoverageRecord unshaped"

DIR="$(scratch pre-v118)"
# Delete EVERY shape targeting the class, not one shape by name. Two target it
# as of v1.19 (clinical:CoverageRecordShape and
# clinical:CoverageTypeVocabularyShape), and a by-name deletion silently stopped
# reproducing the pre-v1.18 state the moment the second one landed -- which is
# how this suite caught its own staleness. Keyed on the TARGET so it keeps
# working however the shapes are later split, renamed or merged.
"$PYTHON" - "$DIR/$CLIN_SHAPES" <<'DELSHAPE'
import re, sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().split("\n")
out, i, removed = [], 0, 0
while i < len(lines):
    if re.match(r"^clinical:\S+ a sh:NodeShape", lines[i]):
        end = i
        while end < len(lines) and lines[end].strip() != "] .":
            end += 1
        block = lines[i:end + 1]
        if any("sh:targetClass clinical:CoverageRecord" in b for b in block):
            removed += 1
            i = end + 1
            continue
    out.append(lines[i])
    i += 1
if removed == 0:
    sys.exit("no shape targeting clinical:CoverageRecord was found to delete")
open(path, "w", encoding="utf-8").write("\n".join(out))
DELSHAPE

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
echo "4. A newly marked class with no shape, baseline present"

DIR="$(scratch new-class)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchTestRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Scratch Test Record"@en .
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

clinical:ScratchTestRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Scratch Test Record"@en .
EOF
cat >> "$DIR/$CLIN_SHAPES" <<'EOF'

clinical:ScratchTestRecordShape a sh:NodeShape ;
    sh:targetClass clinical:ScratchTestRecord ;
    rdfs:label "Scratch Test Record Shape"@en ;
    sh:property [
        sh:path cascade:schemaVersion ;
        sh:datatype xsd:string ;
        sh:minCount 1
    ] .
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
    rdfs:label "Imaging Study Shape"@en ;
    sh:property [
        sh:path cascade:schemaVersion ;
        sh:datatype xsd:string ;
        sh:minCount 1
    ] .
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
# 8. AN UNMARKED CLASS IS OUT OF SCOPE and must not be reported. This is the
#    scope boundary drawn deliberately: the unmarked population mixes value
#    enumerations with record classes, and separating them is a vocabulary
#    judgement rather than a check's. Marking one is how it enters.
# ---------------------------------------------------------------------------
echo ""
echo "8. Scope boundary: an unmarked class is not reported"

DIR="$(scratch no-superclass)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchRootlessClass a owl:Class ;
    rdfs:label "Scratch Rootless Class"@en .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "an unmarked class is out of scope (exit 0)"
else
  fail "an unmarked class was reported" "$OUT"
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
# 12. A shape that names a class in sh:targetClass but carries NO constraint
#     does not make that class covered. A bare target plus an rdfs:label still
#     returns conforms:true over every record having examined nothing, which is
#     verbatim the defect this check exists to catch -- so accepting it would
#     let a contributor clear a baseline entry, and the ratchet, without
#     writing a single constraint.
# ---------------------------------------------------------------------------
echo ""
echo "12. A constraint-free shape does not count as coverage"

DIR="$(scratch empty-shape)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchHollowRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Scratch Hollow Record"@en .
EOF
cat >> "$DIR/$CLIN_SHAPES" <<'EOF'

clinical:ScratchHollowRecordShape a sh:NodeShape ;
    sh:targetClass clinical:ScratchHollowRecord ;
    rdfs:label "Scratch Hollow Record Shape"@en .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "a class targeted only by a constraint-free shape fails (exit $STATUS)"
else
  fail "a constraint-free shape was accepted as coverage" "$OUT"
fi
if echo "$OUT" | grep -q "clinical:ScratchHollowRecord"; then
  pass "names clinical:ScratchHollowRecord"
else
  fail "failed without naming clinical:ScratchHollowRecord" "$OUT"
fi

# Negative control: the SAME shape with one sh:property added must pass, so the
# failure above is the absent constraint and not merely the new class.
DIR="$(scratch empty-shape-control)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchHollowRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Scratch Hollow Record"@en .
EOF
cat >> "$DIR/$CLIN_SHAPES" <<'EOF'

clinical:ScratchHollowRecordShape a sh:NodeShape ;
    sh:targetClass clinical:ScratchHollowRecord ;
    rdfs:label "Scratch Hollow Record Shape"@en ;
    sh:property [
        sh:path cascade:schemaVersion ;
        sh:datatype xsd:string ;
        sh:minCount 1
    ] .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "negative control: the same shape carrying one constraint passes"
else
  fail "negative control failed, so case 12 proves nothing" "$OUT"
fi

# ---------------------------------------------------------------------------
# 13. THE MARKER IS NOT INHERITED. An unmarked subclass of a marked class is
#     OUT of scope, and this case asserts it in both directions.
#
#     Through core v3.12 the population was the transitive rdfs:subClassOf
#     closure over prov:Entity, so a child inherited membership from its parent.
#     core v3.13 made membership an explicit triple (jayostis/spec#34, #50) and
#     inheritance went with it, deliberately: validation/index.md's rule is that
#     a parent's shape does NOT reach a child over a pod's data graph, so a
#     child that inherited the OBLIGATION while inheriting none of the
#     constraint would be owed a verdict nothing could ever deliver.
#
#     The six clinical: document subtypes are the live case, and they each carry
#     their own marker.
# ---------------------------------------------------------------------------
echo ""
echo "13. The marker is not inherited: an unmarked child is out of scope"

DIR="$(scratch not-inherited)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchParentRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Scratch Parent Record"@en .

clinical:ScratchChildRecord a owl:Class ;
    rdfs:label "Scratch Child Record"@en ;
    rdfs:subClassOf clinical:ScratchParentRecord .
EOF
cat >> "$DIR/$CLIN_SHAPES" <<'EOF'

clinical:ScratchParentRecordShape a sh:NodeShape ;
    sh:targetClass clinical:ScratchParentRecord ;
    rdfs:label "Scratch Parent Record Shape"@en ;
    sh:property [
        sh:path cascade:schemaVersion ;
        sh:datatype xsd:string ;
        sh:minCount 1
    ] .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "an unmarked child of a marked class is out of scope (exit 0)"
else
  fail "an unmarked child was reported" "Membership is the marker triple alone. If the child entered the population
        it was inherited through rdfs:subClassOf, which is the pre-v3.13 rule
        jayostis/spec#34 ruled out. $OUT"
fi
if echo "$OUT" | grep -q "clinical:ScratchChildRecord"; then
  fail "named the unmarked child" "$OUT"
else
  pass "does not name clinical:ScratchChildRecord"
fi

# The other direction, and what makes the case above mean something: MARK the
# child and it is in scope immediately. Without this, case 13 would also pass on
# a check that had stopped seeing scratch classes at all.
DIR="$(scratch marked-child)"
cat >> "$DIR/$CLIN_TTL" <<'EOF'

clinical:ScratchParentRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Scratch Parent Record"@en .

clinical:ScratchChildRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Scratch Child Record"@en ;
    rdfs:subClassOf clinical:ScratchParentRecord .
EOF
cat >> "$DIR/$CLIN_SHAPES" <<'EOF'

clinical:ScratchParentRecordShape a sh:NodeShape ;
    sh:targetClass clinical:ScratchParentRecord ;
    rdfs:label "Scratch Parent Record Shape"@en ;
    sh:property [
        sh:path cascade:schemaVersion ;
        sh:datatype xsd:string ;
        sh:minCount 1
    ] .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ] && echo "$OUT" | grep -q "clinical:ScratchChildRecord"; then
  pass "marking the child brings it into scope and it is named"
else
  fail "a MARKED unshaped child was not reported" "If this passes the check is not seeing scratch classes at all, and the
        assertion above proves nothing. $OUT"
fi
if echo "$OUT" | grep -qE "clinical:ScratchParentRecord$"; then
  fail "reported the shaped parent as unshaped" "$OUT"
else
  pass "does not report the shaped parent"
fi

# ---------------------------------------------------------------------------
# 14. A baselined class that has been REMOVED from the ontology is a different
#     event from one that has been SHAPED, and must not be reported as the
#     latter. Both empty the entry, but "remove the entry, the class is shaped"
#     sends the reader looking for a shape nobody ever wrote.
# ---------------------------------------------------------------------------
echo ""
echo "14. A baselined class that no longer exists is reported as removed"

DIR="$(scratch removed-class)"
"$PYTHON" - "$DIR/ontologies/coverage/v1/coverage.ttl" <<'DELCLASS'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
block = re.search(r"^coverage:DenialNotice a owl:Class[^;]*;.*?\.\n", text, re.S | re.M)
if not block:
    sys.exit("coverage:DenialNotice declaration not found to delete")
open(path, "w", encoding="utf-8").write(text[:block.start()] + text[block.end():])
DELCLASS

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "a baselined class that was deleted fails (exit $STATUS)"
else
  fail "deleting a baselined class did not fail the check" "$OUT"
fi
if echo "$OUT" | grep -q "no longer exist"; then
  pass "reports it as no longer existing"
else
  fail "did not distinguish a removed class from a shaped one" "$OUT"
fi
if echo "$OUT" | grep -q "no longer unshaped"; then
  fail "reported a REMOVED class as 'no longer unshaped'" "$OUT"
else
  pass "does not claim the removed class was shaped"
fi

# Negative control for case 14: the SHAPED case keeps its own wording, so the
# two remediations stay distinguishable in both directions.
DIR="$(scratch removed-class-control)"
cat >> "$DIR/$CLIN_SHAPES" <<'EOF'

clinical:ImagingStudyShape a sh:NodeShape ;
    sh:targetClass clinical:ImagingStudy ;
    rdfs:label "Imaging Study Shape"@en ;
    sh:property [
        sh:path cascade:schemaVersion ;
        sh:datatype xsd:string ;
        sh:minCount 1
    ] .
EOF

OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if echo "$OUT" | grep -q "no longer unshaped"; then
  pass "a baselined class that WAS shaped still reports as shaped"
else
  fail "the shaped case lost its own wording" "$OUT"
fi
if echo "$OUT" | grep -q "no longer exist"; then
  fail "reported a SHAPED class as no longer existing" "$OUT"
else
  pass "does not claim the shaped class was removed"
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
