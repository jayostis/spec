#!/bin/sh
# test-record-class-declarations.sh
#
# Regression suite for a VOCABULARY fact, not for a script. The other
# test-check-*.sh suites ask whether a check can still fail; this one asks
# whether the ontologies still say something true about themselves, using
# check-class-coverage.py UNCHANGED as the instrument.
#
# THE RULE
#
# rdfs:subClassOf prov:Entity means, in this specification, that instances of
# the class are stored record data. A class that carries its own data
# properties is a record class, so it must declare one of the PROV record
# superclasses -- and is then either judged by a shape or recorded in
# scripts/known-unshaped-classes.json as owing one.
#
# THE DEFECT UNDER TEST
#
# Seven classes carried data properties, held record data, were targeted by no
# shape, and declared no rdfs:subClassOf at all. check-class-coverage.py reads
# that chain to decide what bears records, so it could not see them: the gate
# reported PASS over all seven, and they were absent from the baseline too,
# because that file is the gate's output. Invisible in both directions.
# conformance/KNOWN_FAILURES.json had been carrying two of them
# (coverage:ClaimRecord, coverage:BenefitStatement) as UNSHAPED ownedBy spec --
# a downstream repository reporting a gap this repository's own gate could not.
#
# WHY THE FIX IS IN THE VOCABULARY AND NOT IN THE CHECK
#
# Pointing the check at every class with no rdfs:subClassOf reports 57 unshaped
# classes, of which 43 are value enumerations -- evidence:VerdictValue,
# diabetes:MealType, genomics:ZygosityValue and 40 more, each with zero
# properties and each the range of some predicate. Baselining those would
# record 43 obligations that can never be discharged, because a code-list
# member has nothing for a shape to constrain. That is verbatim the defect
# jayostis/spec#12 removed for eleven terms when cascade:DataProvenance and its
# ten values lost a prov:Entity claim they should never have made.
#
# So case 2 is not decoration. It is the assertion that catches someone
# reaching for the easier change later, and case 3's exact count is the same
# assertion stated as a number: the population grows by the seven declared and
# by nothing else.
#
# MAINTENANCE
#
# HEAD_RECORD_CLASSES and HEAD_SHAPED pin the population measured at ff27770.
# A later change that legitimately adds or shapes a record class updates them
# in the same commit -- that edit is the point, not an inconvenience: it is
# what makes a silent change in the population impossible.
#
# Usage: ./scripts/test-record-class-declarations.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-class-coverage.py"
TARGETS_CHECK="$SCRIPT_DIR/check-shape-targets.py"
SEVERITY_CHECK="$SCRIPT_DIR/check-nested-severity.py"
PYTHON="${PYTHON:-python3}"

# The seven classes this suite requires to declare a PROV record superclass,
# with the count of data properties declaring rdfs:domain of each and whether
# anything declares it as an rdfs:range, measured over ontologies/**/*.ttl:
#
#   props  isRangeOf  class
#       9          0  coverage:BenefitStatement
#       7          1  coverage:ClaimRecord
#       4          0  cascade:AIDiscardedExtraction
#       4          1  checkup:CheckInSettings
#       4          1  workbench:Hypothesis
#       3          1  cascade:ConflictDetail
#       2          1  workbench:Pin
DECLARED_RECORD_CLASSES="coverage:BenefitStatement coverage:ClaimRecord \
cascade:AIDiscardedExtraction checkup:CheckInSettings workbench:Hypothesis \
cascade:ConflictDetail workbench:Pin"

# Value enumerations: zero properties, each the range of some predicate,
# nothing for a shape to constrain. These must NOT enter the population. The
# cascade: terms after ConsentScope are the ones jayostis/spec#12 removed from
# it, and cascade:ConsentScope is core v3.11's code list, kept out under the
# same rule when it was added.
VALUE_ENUMERATIONS="evidence:VerdictValue diabetes:MealType \
genomics:ZygosityValue cascade:DataProvenance cascade:ConsentScope \
cascade:ConsumerGenerated cascade:ClinicalGenerated cascade:DeviceGenerated \
cascade:SelfReported cascade:PatientReported cascade:ConsumerWellness \
cascade:EHRVerified cascade:ScannedDocument cascade:AIExtracted"

# Measured at ff27770, before any class in DECLARED_RECORD_CLASSES declares a
# PROV superclass.
HEAD_RECORD_CLASSES=103
HEAD_SHAPED=69
DECLARED_COUNT=7

EXPECTED_RECORD_CLASSES=$((HEAD_RECORD_CLASSES + DECLARED_COUNT))

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

echo ""
echo "=========================================================="
echo "  record-class declaration suite"
echo "  spec root: $SPEC_ROOT"
echo "=========================================================="

# ---------------------------------------------------------------------------
# 1. THE OUTER LOOP. Every class in DECLARED_RECORD_CLASSES is inside the
#    population check-class-coverage.py examines, and none of them is shaped,
#    so --no-baseline names each one. This is the whole issue: today the run
#    reports nothing about any of them, and a gate that cannot see a class
#    cannot judge it.
# ---------------------------------------------------------------------------
echo ""
echo "1. Each declared record class is visible to the gate"

NB_OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" --no-baseline 2>&1)"
NB_STATUS=$?

if [ $NB_STATUS -ne 0 ]; then
  pass "--no-baseline exits non-zero, so it is reporting a list (exit $NB_STATUS)"
else
  fail "--no-baseline exited 0, so it named nothing at all" "$NB_OUT"
fi

for CLS in $DECLARED_RECORD_CLASSES; do
  if printf '%s\n' "$NB_OUT" | grep -qE "^[[:space:]]+${CLS}\$"; then
    pass "$CLS is a record class the gate can see"
  else
    fail "$CLS is invisible to the gate" \
"it carries data properties and holds record data, but declares no
        rdfs:subClassOf prov:Entity, so check-class-coverage.py never
        examines it and it is neither shaped nor recorded as owing a shape."
  fi
done

# ---------------------------------------------------------------------------
# 2. The value enumerations stay OUT. This is what distinguishes declaring the
#    truth about seven record classes from widening the check over all 57
#    classes that declare no superclass.
# ---------------------------------------------------------------------------
echo ""
echo "2. Value enumerations do not enter the population"

ENUM_LEAKED=""
for CLS in $VALUE_ENUMERATIONS; do
  if printf '%s\n' "$NB_OUT" | grep -qE "^[[:space:]]+${CLS}\$"; then
    ENUM_LEAKED="$ENUM_LEAKED $CLS"
  fi
done
if [ -z "$ENUM_LEAKED" ]; then
  pass "no value enumeration is reported as an unshaped record class"
else
  fail "value enumeration(s) entered the population:$ENUM_LEAKED" \
"A code-list member has nothing for a shape to constrain, so baselining it
        records an obligation that can never be discharged -- the defect
        jayostis/spec#12 removed for eleven terms. If these arrived by
        widening the check's scope, that is the wrong fix."
fi

# ---------------------------------------------------------------------------
# 3. The population grows by exactly the number declared, and `shaped` does not
#    move. The count is the enumeration assertion restated as a number: it
#    fails both if a declared class is missing and if anything else was
#    declared record-bearing alongside it.
# ---------------------------------------------------------------------------
echo ""
echo "3. The population grows by exactly $DECLARED_COUNT, shaped unchanged"

OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" 2>&1)"
STATUS=$?
COUNT="$(printf '%s\n' "$OUT" | sed -n 's/^[[:space:]]*record classes:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
SHAPED="$(printf '%s\n' "$OUT" | sed -n 's/^[[:space:]]*shaped:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"

if [ "$COUNT" = "$EXPECTED_RECORD_CLASSES" ]; then
  pass "record classes: $COUNT ($HEAD_RECORD_CLASSES + $DECLARED_COUNT)"
else
  fail "record classes: $COUNT, expected $EXPECTED_RECORD_CLASSES" \
"$HEAD_RECORD_CLASSES at ff27770 plus the $DECLARED_COUNT this suite requires.
        Below expected means a declaration is missing; above means something
        was declared record-bearing that this suite does not name."
fi

if [ "$SHAPED" = "$HEAD_SHAPED" ]; then
  pass "shaped: $SHAPED, unchanged"
else
  fail "shaped: $SHAPED, expected $HEAD_SHAPED" \
"No previously-visible class may change state. The declared classes are
        unshaped and belong in the baseline, not in shaped."
fi

# ---------------------------------------------------------------------------
# 4. The gate is green again once the declared classes are recorded, and
#    nothing else moved. Between the declarations and the baseline entries this
#    case is red, which is the point: the entry is what turns it green, and it
#    is a committed edit.
# ---------------------------------------------------------------------------
echo ""
echo "4. The gate is green and the neighbouring checks still are"

if [ $STATUS -eq 0 ]; then
  pass "check-class-coverage.py exits 0 (every record class shaped or baselined)"
else
  fail "check-class-coverage.py exits $STATUS" "$OUT"
fi

OUT="$("$PYTHON" "$TARGETS_CHECK" "$SPEC_ROOT" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "check-shape-targets.py still exits 0"
else
  fail "check-shape-targets.py exits $STATUS" "$OUT"
fi

OUT="$("$PYTHON" "$SEVERITY_CHECK" "$SPEC_ROOT" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "check-nested-severity.py still exits 0"
else
  fail "check-nested-severity.py exits $STATUS" "$OUT"
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
