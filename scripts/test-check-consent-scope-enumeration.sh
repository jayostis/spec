#!/bin/sh
# test-check-consent-scope-enumeration.sh
#
# Regression suite for check-consent-scope-enumeration.py.
#
# THE DEFECT UNDER TEST. D-CONSENT-1 ratified the consent scope value set as
# social-history / substance-use / mental-health and ratified it OPEN --
# "sh:in at sh:Warning at most, never sh:Violation", because "a closed list
# missing a member rejects conformant data". core.shapes.ttl v1.8 published the
# opposite: one member, at sh:Violation. A record tagged substance-use or
# mental-health is rejected today.
#
# WHAT THE SUITE IS FOR. The check reasons over the shapes graph, so its own
# assertions can rot silently: an assertion that can no longer fail reports PASS
# forever and reads exactly like an earned one. Every case here is therefore
# paired with a NEGATIVE CONTROL -- a scratch copy of the corpus with one defect
# reintroduced, which the check must name and fail on.
#
# The controls mutate the PARSED GRAPH and re-serialize, never the text. A
# regex control would pin the defect to today's file layout, so the first time
# someone moved the property block to a top-level sh:PropertyShape the control
# would quietly rewrite some unrelated shape and pass having tested nothing.
# The check itself is location-agnostic; its controls have to be too.
#
# Nothing is skipped when a dependency is missing: a suite that skips itself
# reports green while testing nothing.
#
# Usage: ./scripts/test-check-consent-scope-enumeration.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-consent-scope-enumeration.py"
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CORE_SHAPES="ontologies/core/v1/core.shapes.ttl"
CORE_TTL="ontologies/core/v1/core.ttl"

# The mutators shared by the controls. Each takes a file and a mode, edits the
# parsed graph, and writes the file back.
MUTATE="$WORK/mutate.py"
cat > "$MUTATE" <<'MUTATOR'
"""Reintroduce one consent-scope defect into a scratch copy, via the graph."""
import sys

from rdflib import BNode, Graph, Namespace, RDF
from rdflib.collection import Collection

SH = Namespace("http://www.w3.org/ns/shacl#")
C = Namespace("https://ns.cascadeprotocol.org/core/v1#")

path, mode = sys.argv[1], sys.argv[2]
g = Graph()
g.parse(path, format="turtle")

scope_shapes = list(g.subjects(SH.path, C.consentScope))
in_shapes = [s for s in scope_shapes if g.value(s, SH["in"]) is not None]


def drop_list(graph, head):
    while head is not None and head != RDF.nil:
        nxt = graph.value(head, RDF.rest)
        graph.remove((head, RDF.first, None))
        graph.remove((head, RDF.rest, None))
        head = nxt


def set_severity(shapes, severity):
    for s in shapes:
        g.remove((s, SH.severity, None))
        g.add((s, SH.severity, severity))


if mode == "close-enumeration":
    # The v1.8 defect: one member, the other ratified scopes gone.
    if not in_shapes:
        sys.exit("control found no sh:in on cascade:consentScope to close")
    for s in in_shapes:
        old = g.value(s, SH["in"])
        g.remove((s, SH["in"], old))
        drop_list(g, old)
        head = BNode()
        Collection(g, head, [C.SocialHistoryConsent])
        g.add((s, SH["in"], head))

elif mode == "harden-value-set":
    # The value set republished as a rejection.
    if not in_shapes:
        sys.exit("control found no sh:in on cascade:consentScope to harden")
    set_severity(in_shapes, SH.Violation)

elif mode == "demote-everything":
    # The whole property block softened instead of only the value set.
    if not scope_shapes:
        sys.exit("control found no property shape on cascade:consentScope")
    set_severity(scope_shapes, SH.Warning)

elif mode == "undeclare-scope":
    # An sh:in member pointing at an IRI nothing declares.
    if not list(g.triples((C.SocialHistoryConsent, RDF.type, None))):
        sys.exit("control found no cascade:SocialHistoryConsent declaration")
    g.remove((C.SocialHistoryConsent, RDF.type, None))

else:
    sys.exit(f"unknown mutation mode: {mode}")

g.serialize(destination=path, format="turtle")
MUTATOR

# A scratch copy of the ontology tree, which a case may mutate freely.
scratch() {
  dir="$WORK/$1"
  mkdir -p "$dir"
  cp -R "$SPEC_ROOT/ontologies" "$dir/ontologies"
  echo "$dir"
}

# Run the check against a scratch root and require it to fail naming one tag.
expect_caught() {
  dir="$1"
  tag="$2"
  label="$3"
  out="$("$PYTHON" "$CHECK" "$dir" 2>&1)"
  status=$?
  if [ $status -ne 0 ] && echo "$out" | grep -q "FAIL  \[$tag\]"; then
    pass "$label"
  else
    fail "$label -- NOT caught (exit $status)" "$out"
  fi
}

# Run the check against a scratch root and require it to pass. Used by the
# POSITIVE controls: a corpus that is legitimately allowed to look like this
# must not be reported as a defect.
expect_clean() {
  dir="$1"
  label="$2"
  out="$("$PYTHON" "$CHECK" "$dir" 2>&1)"
  status=$?
  if [ $status -eq 0 ]; then
    pass "$label"
  else
    fail "$label -- wrongly reported (exit $status)" "$out"
  fi
}

echo ""
echo "=========================================================="
echo "  check-consent-scope-enumeration.py regression suite"
echo "=========================================================="

# ---------------------------------------------------------------------------
echo ""
echo "1. The repository itself"

OUT="$("$PYTHON" "$CHECK" "$SPEC_ROOT" 2>&1)"
STATUS=$?
if [ $STATUS -eq 0 ]; then
  pass "check passes against this repository"
else
  fail "check FAILED against this repository (exit $STATUS)" "$OUT"
fi

# ---------------------------------------------------------------------------
echo ""
echo "2. Negative control: a closed one-member enumeration (the v1.8 defect)"

DIR="$(scratch closed)"
if "$PYTHON" "$MUTATE" "$DIR/$CORE_SHAPES" close-enumeration; then
  expect_caught "$DIR" CS2 "a one-member sh:in fails CS2"
else
  fail "control setup failed" "could not close the enumeration"
fi

# ---------------------------------------------------------------------------
echo ""
echo "3. Negative control: the value set republished at sh:Violation"

DIR="$(scratch hardened)"
if "$PYTHON" "$MUTATE" "$DIR/$CORE_SHAPES" harden-value-set; then
  expect_caught "$DIR" CS3 "a Violation-severity value set fails CS3"
else
  fail "control setup failed" "could not harden the value set"
fi

# ---------------------------------------------------------------------------
echo ""
echo "4. Negative control: the whole property block demoted rather than split"
#
# This is the failure mode the block split exists to prevent. Demoting the
# block instead of only the value set turns "two consent scopes on one record"
# and "a literal instead of an IRI" into warnings, which nothing asked for.

DIR="$(scratch demoted)"
if "$PYTHON" "$MUTATE" "$DIR/$CORE_SHAPES" demote-everything; then
  expect_caught "$DIR" CS4 "demoting the structural constraints fails CS4"
else
  fail "control setup failed" "could not demote the property block"
fi

# ---------------------------------------------------------------------------
echo ""
echo "5. Negative control: an sh:in member that no ontology declares"

DIR="$(scratch dangling)"
if "$PYTHON" "$MUTATE" "$DIR/$CORE_TTL" undeclare-scope; then
  expect_caught "$DIR" CS1 "an undeclared scope member fails CS1"
else
  fail "control setup failed" "could not undeclare a scope"
fi

# ---------------------------------------------------------------------------
echo ""
echo "6. Negative control: sh:node reaching cascade:ConsentScopeShape"
#
# Rule S5. A Warning on a shape something reaches by sh:node is delivered to the
# referring class as a Violation, so CS3's demotion would be nominal only. This
# control is what makes CS5 evidence: CS5 passes against the repository today,
# and an assertion never seen to fail has proved nothing.

DIR="$(scratch nested)"
cat >> "$DIR/$CORE_SHAPES" <<'EOF'

cascade:ControlNestingShape a sh:NodeShape ;
    sh:targetClass cascade:ControlNestingTarget ;
    sh:property [
        sh:path cascade:consentScope ;
        sh:node cascade:ConsentScopeShape
    ] .
EOF
expect_caught "$DIR" CS5 "an sh:node reference to ConsentScopeShape fails CS5"

# ---------------------------------------------------------------------------
echo ""
echo "7. Negative control: sh:or and sh:not reaching cascade:ConsentScopeShape"
#
# Rule S5 again, by the other doors. sh:node and sh:qualifiedValueShape are not
# the only parameters that collapse a referenced shape's result set to a boolean
# and re-report it at the REFERRING shape's severity: sh:or, sh:and, sh:xone and
# sh:not do it too. Either of these would deliver the sh:in Warning to the
# referring class as a rejection for an unrecognised scope IRI -- CS3's demotion
# nominal again -- so CS5, which is documented as the precondition that makes
# CS3 real, has to see them.
#
# check-nested-severity.py does not backstop this: its NESTED_SHAPE_PARAMS is
# the same pair, and it walks sh:or / sh:and / sh:xone only for reachability
# FROM a shape already referenced by that pair.

DIR="$(scratch nested-or)"
cat >> "$DIR/$CORE_SHAPES" <<'EOF'

cascade:ControlOrNestingShape a sh:NodeShape ;
    sh:targetClass cascade:ControlOrNestingTarget ;
    sh:property [
        sh:path cascade:consentScope ;
        sh:or ( cascade:ConsentScopeShape cascade:ControlOtherShape )
    ] .
EOF
expect_caught "$DIR" CS5 "an sh:or reference to ConsentScopeShape fails CS5"

DIR="$(scratch nested-not)"
cat >> "$DIR/$CORE_SHAPES" <<'EOF'

cascade:ControlNotNestingShape a sh:NodeShape ;
    sh:targetClass cascade:ControlNotNestingTarget ;
    sh:property [
        sh:path cascade:consentScope ;
        sh:not cascade:ConsentScopeShape
    ] .
EOF
expect_caught "$DIR" CS5 "an sh:not reference to ConsentScopeShape fails CS5"

# ---------------------------------------------------------------------------
echo ""
echo "8. Positive control: ratchet step 2 on another shape must not fail CS4"
#
# CS4's subject is cascade:ConsentScopeShape's OWN block split -- structural
# constraints in a block carrying no sh:in, at sh:Violation. It is not a claim
# on every shape in the corpus that mentions the predicate.
#
# core.shapes.ttl documents the next move as exactly such a shape: sh:minCount 1
# at sh:Warning on clinical:SocialHistoryRecordShape, once the reference
# producers emit a scope. That is a presence constraint on a record class, not a
# softening of the value shape, and CS4 must not fire on it -- otherwise this
# repository's own documented next step turns CI red and the cheapest-looking
# fix is to weaken CS4. Other shapes' severities are the general gate's business.

DIR="$(scratch ratchet2)"
cat >> "$DIR/$CORE_SHAPES" <<'EOF'

cascade:ControlRatchetStep2Shape a sh:NodeShape ;
    sh:targetClass cascade:ControlRatchetStep2Target ;
    sh:property [
        sh:path cascade:consentScope ;
        sh:minCount 1 ;
        sh:severity sh:Warning ;
        sh:message "should carry a consent scope"@en
    ] .
EOF
expect_clean "$DIR" "a Warning sh:minCount on another shape does not fail CS4"

# ---------------------------------------------------------------------------
echo ""
echo "9. Missing-corpus control: an empty root must error, not pass"

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
echo ""
echo "=========================================================="
echo "  passed:  $PASSED"
echo "  failed:  $FAILED"
echo "  total:   $((PASSED + FAILED))"
echo "=========================================================="
echo ""

[ "$FAILED" -eq 0 ] || exit 1
exit 0
