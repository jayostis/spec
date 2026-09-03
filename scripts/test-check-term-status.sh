#!/bin/sh
# test-check-term-status.sh
#
# Regression suite for check-term-status.py.
#
# The defect under test: a draft vocabulary states its maturity once, in prose,
# so a consumer cannot tell which individual terms are safe to build on. The fix
# is vs:term_status on every term. The risk is that the annotation pass MISSES
# terms and nobody notices, which is not hypothetical: the pass that introduced
# these annotations silently skipped 96 of 411 terms -- every term preceded by a
# section comment -- and reported success. Only reading the parsed graph caught
# it. See scripts/check-term-status.py.
#
# Every assertion below is paired with a NEGATIVE CONTROL: a scratch copy of a
# real ontology with one defect deliberately reintroduced, which the check must
# catch and must name. A check that has only ever been observed passing is not
# evidence that it can fail.
#
# The suite also proves the check is not vacuous: run against a corpus with no
# terms at all, it must report FAIL because it examined nothing, rather than
# PASS because it found nothing to complain about.
#
# Usage: ./scripts/test-check-term-status.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-term-status.py"
PYTHON="${PYTHON:-python3}"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }

# A missing parser is a hard failure, never a skip. Skipping the suite because a
# dependency is absent reports green while testing nothing, which is the exact
# class of defect this file guards against.
if ! "$PYTHON" -c "import rdflib" 2>/dev/null; then
  echo "ERROR: $PYTHON cannot import rdflib, so this suite would test nothing."
  echo "       Install it:  $PYTHON -m pip install -r scripts/requirements.txt"
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SUBJECT="$SPEC_ROOT/ontologies/workbench/v1-draft/workbench.ttl"

echo "check-term-status.py regression suite"
echo ""

# ── 1. The repository itself passes ───────────────────────────────────────────
if (cd "$SPEC_ROOT" && "$PYTHON" "$CHECK" >/dev/null 2>&1); then
  pass "every draft term in this repository declares a vs:term_status"
else
  (cd "$SPEC_ROOT" && "$PYTHON" "$CHECK" 2>&1 | tail -20)
  fail "every draft term in this repository declares a vs:term_status" \
       "the check reports a problem against unmodified sources"
fi

# ── 2. Negative control: a term with its status removed ───────────────────────
# The exact defect the first annotation pass shipped.
cp "$SUBJECT" "$WORK/missing.ttl"
"$PYTHON" - "$WORK/missing.ttl" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
old = ' ;\n    vs:term_status "unstable" .'
assert s.count(old) > 0, "fixture no longer contains an annotated term"
p.write_text(s.replace(old, ' .', 1), encoding="utf-8")
PY
OUT="$("$PYTHON" "$CHECK" "$WORK/missing.ttl" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "MISSING vs:term_status"; then
  pass "a term with no vs:term_status is caught and named"
else
  fail "a term with no vs:term_status is caught and named" \
       "check did not fail, or did not name the term: $OUT"
fi

# ── 3. Negative control: an unrecognised status value ─────────────────────────
cp "$SUBJECT" "$WORK/badvalue.ttl"
sed 's/vs:term_status "unstable"/vs:term_status "prettystable"/' "$SUBJECT" > "$WORK/badvalue.ttl"
OUT="$("$PYTHON" "$CHECK" "$WORK/badvalue.ttl" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "INVALID value"; then
  pass "a status outside {unstable,testing,stable,archaic} is caught"
else
  fail "a status outside {unstable,testing,stable,archaic} is caught" \
       "check did not fail on an invented status value: $OUT"
fi

# ── 4. Negative control: owl:deprecated disagreeing with term_status ──────────
# Two machine-readable maturity signals that contradict each other are worse
# than one, so the pairing is enforced rather than assumed.
cp "$SPEC_ROOT/ontologies/evidence/v1-draft/evidence.ttl" "$WORK/deprecated.ttl"
sed 's/vs:term_status "archaic"/vs:term_status "stable"/' \
    "$SPEC_ROOT/ontologies/evidence/v1-draft/evidence.ttl" > "$WORK/deprecated.ttl"
OUT="$("$PYTHON" "$CHECK" "$WORK/deprecated.ttl" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "owl:deprecated but term_status"; then
  pass "owl:deprecated with a non-archaic status is caught"
else
  fail "owl:deprecated with a non-archaic status is caught" \
       "check did not fail on a deprecated term marked stable: $OUT"
fi

# ── 5. Non-vacuity: nothing to check must not read as success ─────────────────
cat > "$WORK/empty.ttl" <<'TTL'
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix dct: <http://purl.org/dc/terms/> .
<https://ns.cascadeprotocol.org/nothing/v1#> a owl:Ontology ;
    dct:title "No terms at all" .
TTL
OUT="$("$PYTHON" "$CHECK" "$WORK/empty.ttl" 2>&1)"
if echo "$OUT" | grep -q "   0 terms"; then
  pass "a corpus with no terms is reported as examining nothing"
else
  fail "a corpus with no terms is reported as examining nothing" \
       "expected a zero-term report: $OUT"
fi

# ── 6. A deprecated class must name a live successor ─────────────────────────
#
# The defect: clinical:CoverageRecord was deprecated in favour of
# coverage:InsurancePlan and its only rdfs:seeAlso pointed at fhir:Coverage, a
# documentation link. The shipped data could say "this class is dead" and not
# "use this instead" -- for the one deprecation whose replacement lives in
# another vocabulary. See jayostis/spec#50.
cat > "$WORK/dead-no-successor.ttl" <<'TTL'
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix vs: <http://www.w3.org/2003/06/sw-vocab-status/ns#> .
@prefix probe: <https://ns.cascadeprotocol.org/probe/v1#> .
@prefix fhir: <http://hl7.org/fhir/> .
probe:DeadClass a owl:Class ;
    rdfs:label "Dead Class"@en ;
    owl:deprecated true ;
    rdfs:seeAlso fhir:Coverage ;
    vs:term_status "archaic" .
TTL
OUT="$("$PYTHON" "$CHECK" "$WORK/dead-no-successor.ttl" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "DeadClass"; then
  pass "a deprecated class whose only rdfs:seeAlso is external is reported"
else
  fail "a deprecated class whose only rdfs:seeAlso is external is reported" \
       "an external documentation link is not a successor: $OUT"
fi

# The cure, and the proof the rule is satisfiable: a seeAlso to a live Cascade
# term clears it. The successor is a PROPERTY here, not a class -- which is the
# evidence:VerdictValue case, a flat enumeration replaced by facet properties.
cat > "$WORK/dead-with-successor.ttl" <<'TTL'
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix vs: <http://www.w3.org/2003/06/sw-vocab-status/ns#> .
@prefix probe: <https://ns.cascadeprotocol.org/probe/v1#> .
@prefix fhir: <http://hl7.org/fhir/> .
probe:DeadClass a owl:Class ;
    rdfs:label "Dead Class"@en ;
    owl:deprecated true ;
    rdfs:seeAlso fhir:Coverage ;
    rdfs:seeAlso probe:livePredicate ;
    vs:term_status "archaic" .
probe:livePredicate a owl:DatatypeProperty ;
    rdfs:label "Live Predicate"@en ;
    vs:term_status "stable" .
TTL
OUT="$("$PYTHON" "$CHECK" "$WORK/dead-with-successor.ttl" 2>&1)"
if [ $? -eq 0 ]; then
  pass "an rdfs:seeAlso to a live Cascade term clears it, property or class"
else
  fail "an rdfs:seeAlso to a live Cascade term clears it, property or class" \
       "the rule must be satisfiable without deleting the external link: $OUT"
fi

# A successor that is itself deprecated is not a successor: it forwards the
# reader to another dead end.
cat > "$WORK/dead-chain.ttl" <<'TTL'
@prefix owl: <http://www.w3.org/2002/07/owl#> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .
@prefix vs: <http://www.w3.org/2003/06/sw-vocab-status/ns#> .
@prefix probe: <https://ns.cascadeprotocol.org/probe/v1#> .
probe:DeadClass a owl:Class ;
    rdfs:label "Dead Class"@en ;
    owl:deprecated true ;
    rdfs:seeAlso probe:AlsoDead ;
    vs:term_status "archaic" .
probe:AlsoDead a owl:Class ;
    rdfs:label "Also Dead"@en ;
    owl:deprecated true ;
    rdfs:seeAlso probe:DeadClass ;
    vs:term_status "archaic" .
TTL
OUT="$("$PYTHON" "$CHECK" "$WORK/dead-chain.ttl" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "DeadClass"; then
  pass "a successor that is itself deprecated does not satisfy the rule"
else
  fail "a successor that is itself deprecated does not satisfy the rule" \
       "pointing at another dead class forwards the reader nowhere: $OUT"
fi

echo ""
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
