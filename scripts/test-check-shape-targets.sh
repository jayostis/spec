#!/bin/sh
# test-check-shape-targets.sh
#
# Regression suite for check-shape-targets.py.
#
# The defect under test: a SHACL shape can reach a class only through an
# rdfs:subClassOf axiom that lives in an ontology file. Validators that merge
# that axiom into the data graph then fire the shape; validators that follow
# SHACL literally do not. The same file is valid under one implementation and
# invalid under the other, and neither is wrong. See validation/index.md.
#
# Every assertion below is paired with a NEGATIVE CONTROL: a scratch copy of
# the repository's ontologies with one entailment dependency deliberately
# reintroduced, which the check must catch and must name. A check that has
# only ever been observed passing is not evidence that it can fail.
#
# The suite also proves the check is not vacuous: it is run against a corpus
# with no subclass relationships at all, where it must report FAIL because it
# examined nothing, not PASS because it found nothing to complain about.
#
# Usage: ./scripts/test-check-shape-targets.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-shape-targets.py"
PYTHON="${PYTHON:-python3}"

PASSED=0
FAILED=0
SKIPPED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }
skip() { SKIPPED=$((SKIPPED + 1)); echo "  SKIP  $1  ($2)"; }

# A missing parser is a hard failure, never a skip. Skipping the whole suite
# because a dependency is absent reports green while testing nothing, which is
# the exact class of defect this file guards against.
if ! "$PYTHON" -c "import rdflib" 2>/dev/null; then
  echo "ERROR: $PYTHON cannot import rdflib, so this suite would test nothing."
  echo "       Install it:  $PYTHON -m pip install -r scripts/requirements.txt"
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CLIN="ontologies/clinical/v1/clinical.shapes.ttl"
GEN="ontologies/genomics/v1-draft/genomics.shapes.ttl"

# Build a scratch copy of the ontology tree that a case can mutate freely.
scratch() {
  dir="$WORK/$1"
  mkdir -p "$dir"
  cp -R "$SPEC_ROOT/ontologies" "$dir/ontologies"
  echo "$dir"
}

echo ""
echo "=========================================================="
echo "  check-shape-targets.py regression suite"
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
  pass "committed shapes satisfy every assertion (exit 0)"
else
  fail "committed shapes do not pass the check (exit $STATUS)" "$OUT"
fi

if echo "$OUT" | grep -q "RESULT: PASS"; then
  pass "reports RESULT: PASS"
else
  fail "did not report RESULT: PASS" "$OUT"
fi

# ---------------------------------------------------------------------------
# 2. Non-vacuity: every assertion must have examined something.
# ---------------------------------------------------------------------------
echo ""
echo "2. Non-vacuity: assertions must examine a non-zero number of cases"

for LETTER in T I C; do
  LINE="$(echo "$OUT" | grep "^PASS  $LETTER ")"
  COUNT="$(echo "$LINE" | sed -n 's/.*: \([0-9][0-9]*\) case.*/\1/p')"
  if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ] 2>/dev/null; then
    pass "assertion $LETTER examined $COUNT case(s)"
  else
    fail "assertion $LETTER reported no case count" "$LINE"
  fi
done

# ---------------------------------------------------------------------------
# 3. Negative control for T (target closure).
#
#    clinical:ConsultationNote is one of six rdfs:subClassOf
#    clinical:ClinicalDocument. Delete its explicit sh:targetClass and it goes
#    back to being reachable only by subclass inference, validating vacuously
#    in a strict validator while its five siblings are checked. The check must
#    catch that and must name the class.
# ---------------------------------------------------------------------------
echo ""
echo "3. Negative control T: remove clinical:ConsultationNote's explicit target"

DIR="$(scratch t)"
grep -v 'sh:targetClass clinical:ConsultationNote' "$SPEC_ROOT/$CLIN" > "$DIR/$CLIN.tmp"
mv "$DIR/$CLIN.tmp" "$DIR/$CLIN"

if [ "$(grep -c 'sh:targetClass clinical:ConsultationNote' "$DIR/$CLIN")" -eq 0 ] &&
   [ "$(grep -c 'sh:targetClass clinical:ConsultationNote' "$SPEC_ROOT/$CLIN")" -eq 1 ]; then
  pass "mutation applied (1 target line removed)"
else
  fail "mutation did not apply as expected" "check the sh:targetClass line in $CLIN"
fi

OUT_T="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_T=$?
if [ $STATUS_T -ne 0 ]; then
  pass "check fails against the reintroduced violation (exit $STATUS_T)"
else
  fail "check PASSED against a known violation" "$OUT_T"
fi

if echo "$OUT_T" | grep -q "^FAIL  T "; then
  pass "assertion T is the one that fails"
else
  fail "assertion T did not fail" "$OUT_T"
fi

if echo "$OUT_T" | grep -q "clinical:ConsultationNote"; then
  pass "names clinical:ConsultationNote in the finding"
else
  fail "did not name the offending class" "$OUT_T"
fi

# ---------------------------------------------------------------------------
# 4. Negative control for I (constraint-set equivalence).
#
#    clinical:ProgressNoteShape carries its parent's constraints with
#    sh:node clinical:ClinicalDocumentShape. Remove that line and the shape
#    still targets ProgressNote, so assertion T stays green, but an entailing
#    validator would apply ClinicalDocumentShape to the node and a strict one
#    would not. Only assertion I can see this.
# ---------------------------------------------------------------------------
echo ""
echo "4. Negative control I: remove ProgressNoteShape's explicit sh:node"

DIR="$(scratch i)"
awk '
  /^clinical:ProgressNoteShape/ { inpn = 1 }
  inpn && /sh:node clinical:ClinicalDocumentShape/ { inpn = 0; next }
  { print }
' "$SPEC_ROOT/$CLIN" > "$DIR/$CLIN.tmp"
mv "$DIR/$CLIN.tmp" "$DIR/$CLIN"

BEFORE_N="$(grep -c 'sh:node clinical:ClinicalDocumentShape' "$SPEC_ROOT/$CLIN")"
AFTER_N="$(grep -c 'sh:node clinical:ClinicalDocumentShape' "$DIR/$CLIN")"
if [ "$AFTER_N" -eq "$((BEFORE_N - 1))" ]; then
  pass "mutation applied (sh:node lines $BEFORE_N -> $AFTER_N)"
else
  fail "mutation did not remove exactly one sh:node line" "$BEFORE_N -> $AFTER_N"
fi

OUT_I="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_I=$?
if [ $STATUS_I -ne 0 ]; then
  pass "check fails against the reintroduced violation (exit $STATUS_I)"
else
  fail "check PASSED against a known violation" "$OUT_I"
fi

if echo "$OUT_I" | grep -q "^FAIL  I "; then
  pass "assertion I is the one that fails"
else
  fail "assertion I did not fail" "$OUT_I"
fi

if echo "$OUT_I" | grep -q "clinical:ProgressNote is targeted"; then
  pass "names clinical:ProgressNote in the finding"
else
  fail "did not name the offending class" "$OUT_I"
fi

if echo "$OUT_I" | grep -q "^PASS  T "; then
  pass "assertion T still passes, so I is not a duplicate of T"
else
  fail "assertion T also failed; the two assertions are not independent" "$OUT_I"
fi

# ---------------------------------------------------------------------------
# 5. Negative control for C (value-class closure).
#
#    genomics:HaplotypeShape accepts components typed genomics:Variant or
#    genomics:CopyNumberVariant. Swap the second alternative for an unrelated
#    class and the site stops accepting the subclass, which an entailing
#    validator would still let through.
# ---------------------------------------------------------------------------
echo ""
echo "5. Negative control C: narrow an sh:class site so it excludes a subclass"

DIR="$(scratch c)"
sed 's/\[ sh:class genomics:CopyNumberVariant \]/[ sh:class genomics:Haplotype ]/' \
  "$SPEC_ROOT/$GEN" > "$DIR/$GEN.tmp"
mv "$DIR/$GEN.tmp" "$DIR/$GEN"

if ! cmp -s "$SPEC_ROOT/$GEN" "$DIR/$GEN"; then
  pass "mutation applied (sh:or alternative replaced)"
else
  fail "mutation did not change the file" "expected '[ sh:class genomics:CopyNumberVariant ]' in $GEN"
fi

OUT_C="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_C=$?
if [ $STATUS_C -ne 0 ]; then
  pass "check fails against the reintroduced violation (exit $STATUS_C)"
else
  fail "check PASSED against a known violation" "$OUT_C"
fi

if echo "$OUT_C" | grep -q "^FAIL  C "; then
  pass "assertion C is the one that fails"
else
  fail "assertion C did not fail" "$OUT_C"
fi

if echo "$OUT_C" | grep -q "genomics:CopyNumberVariant"; then
  pass "names genomics:CopyNumberVariant in the finding"
else
  fail "did not name the excluded subclass" "$OUT_C"
fi

# ---------------------------------------------------------------------------
# 6. Emptiness control.
#
#    A corpus with classes and shapes but no rdfs:subClassOf edges gives
#    assertions T and I nothing to examine. The check must report FAIL, not
#    PASS: an assertion that inspected no cases has established nothing, and
#    reporting it as green is precisely the failure this suite exists to catch.
# ---------------------------------------------------------------------------
echo ""
echo "6. Emptiness control: a corpus with no subclass relationships at all"

DIR="$WORK/empty"
mkdir -p "$DIR/ontologies/example/v1"
cat > "$DIR/ontologies/example/v1/example.ttl" <<'TTL'
@prefix ex:   <https://ns.cascadeprotocol.org/example/v1#> .
@prefix owl:  <http://www.w3.org/2002/07/owl#> .
ex:Alpha a owl:Class .
ex:Beta  a owl:Class .
TTL
cat > "$DIR/ontologies/example/v1/example.shapes.ttl" <<'TTL'
@prefix ex:  <https://ns.cascadeprotocol.org/example/v1#> .
@prefix sh:  <http://www.w3.org/ns/shacl#> .
ex:AlphaShape a sh:NodeShape ;
    sh:targetClass ex:Alpha ;
    sh:property [ sh:path ex:link ; sh:class ex:Beta ] .
TTL

OUT_E="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_E=$?
if [ $STATUS_E -ne 0 ]; then
  pass "check fails when an assertion examined nothing (exit $STATUS_E)"
else
  fail "check PASSED while examining zero cases" "$OUT_E"
fi

if echo "$OUT_E" | grep -q "^EMPTY  *T " && echo "$OUT_E" | grep -q "^EMPTY  *I "; then
  pass "assertions T and I are reported EMPTY, not PASS"
else
  fail "empty assertions were not reported as EMPTY" "$OUT_E"
fi

# ---------------------------------------------------------------------------
# 7. The check must refuse a root with no ontologies rather than pass it.
# ---------------------------------------------------------------------------
echo ""
echo "7. Missing-corpus control: an empty root must error, not pass"

DIR="$WORK/nothing"
mkdir -p "$DIR"
OUT_N="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS_N=$?
if [ $STATUS_N -ne 0 ]; then
  pass "check errors on a root containing no ontologies (exit $STATUS_N)"
else
  fail "check PASSED on a root containing no ontologies" "$OUT_N"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=========================================================="
echo "  passed:  $PASSED"
echo "  failed:  $FAILED"
echo "  skipped: $SKIPPED"
echo "  total:   $((PASSED + FAILED + SKIPPED))"
echo "=========================================================="
echo ""

[ "$FAILED" -eq 0 ] || exit 1
exit 0
