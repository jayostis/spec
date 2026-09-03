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

# ---------------------------------------------------------------------------
# 6. BOTH FILES, NOT EITHER. The rule this repository documents is an entry in
#    the class's own vocabulary context AND in cascade.jsonld. Pooling all seven
#    into one set passed a class named in only one of them -- so a consumer
#    loading coverage.jsonld alone, which is what the per-vocabulary contexts
#    are published for, could not address it.
# ---------------------------------------------------------------------------
echo ""
echo "6. A class named only in cascade.jsonld"

DIR="$(scratch)"
sed -i.bak '/"AppealRecord": "coverage:AppealRecord"/d' "$DIR/contexts/v1/coverage.jsonld"
rm -f "$DIR"/contexts/v1/*.bak
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "exits non-zero"
else
  fail "exits 0 with a class missing from its own vocabulary's context" "$OUT"
fi
if printf '%s\n' "$OUT" | grep -q "coverage:AppealRecord.*coverage.jsonld"; then
  pass "names coverage:AppealRecord and the file it is missing from"
else
  fail "does not say which context the class is missing from" "$OUT"
fi
rm -rf "$DIR"

echo ""
echo "7. A class named only in its own vocabulary's context"

DIR="$(scratch)"
sed -i.bak '/"AppealRecord": "coverage:AppealRecord"/d' "$DIR/contexts/v1/cascade.jsonld"
rm -f "$DIR"/contexts/v1/*.bak
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ]; then
  pass "exits non-zero"
else
  fail "exits 0 with a class missing from the aggregate context" "$OUT"
fi
if printf '%s\n' "$OUT" | grep -q "coverage:AppealRecord.*cascade.jsonld"; then
  pass "names coverage:AppealRecord and the aggregate it is missing from"
else
  fail "does not report the missing aggregate entry" "$OUT"
fi
rm -rf "$DIR"

# ---------------------------------------------------------------------------
# 8. SCOPE AND RESOLUTION MUST AGREE ABOUT WHICH VOCABULARIES EXIST. Scope comes
#    from the context filenames on disk; prefix resolution used a hardcoded
#    six-entry table. Publishing a context for a vocabulary outside the table
#    therefore put its classes in scope while every entry naming them resolved
#    to nothing -- the check failed for classes that were published correctly.
#    Contexts are now resolved against their own prefix declarations.
# ---------------------------------------------------------------------------
echo ""
echo "8. Publishing a context for a vocabulary no table knows about"

DIR="$(scratch)"
N="$("$PYTHON" - "$DIR" <<'PY'
import glob, json, os, sys

from rdflib import Graph, RDF, URIRef

root = sys.argv[1]
BASE = "https://ns.cascadeprotocol.org/"
NS = BASE + "genomics/v1#"
MARKER = URIRef(BASE + "core/v1#RecordClass")

graph = Graph()
for path in sorted(glob.glob(os.path.join(root, "ontologies/genomics/*/*.ttl"))):
    if not path.endswith(".shapes.ttl"):
        graph.parse(path, format="turtle")

names = sorted(str(c)[len(NS):] for c in graph.subjects(RDF.type, MARKER)
               if str(c).startswith(NS))
assert names, "no marked genomics class to publish -- fixture is stale"

published = {"genomics": NS}
published.update({name: "genomics:" + name for name in names})
with open(os.path.join(root, "contexts/v1/genomics.jsonld"), "w",
          encoding="utf-8") as handle:
    json.dump({"@context": published}, handle, indent=2)

# The aggregate owes them an entry too, under keys that collide with nothing.
path = os.path.join(root, "contexts/v1/cascade.jsonld")
with open(path, encoding="utf-8") as handle:
    doc = json.load(handle)
doc["@context"]["genomics"] = NS
for name in names:
    doc["@context"].setdefault("Genomics" + name, "genomics:" + name)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(doc, handle, indent=2)

print(len(names))
PY
)"
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
if [ $? -eq 0 ]; then
  pass "$N correctly published genomics class(es) resolve and pass"
else
  fail "correctly published classes were reported" \
"Scope said genomics was published; resolution did not know the prefix. $OUT"
fi
rm -rf "$DIR"

# The same defect in the other direction: a context that redefines a prefix to
# a DIFFERENT namespace must not be credited with naming the v1 class. Under a
# table, "health:" meant health/v1# whatever the file said.
echo ""
echo "9. A context that redefines its prefix is read as it is written"

DIR="$(scratch)"
sed -i.bak 's|"health": "https://ns.cascadeprotocol.org/health/v1#"|"health": "https://ns.cascadeprotocol.org/health/v2#"|' \
  "$DIR/contexts/v1/health.jsonld"
rm -f "$DIR"/contexts/v1/*.bak
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ] && printf '%s\n' "$OUT" | grep -q "health:LabResultRecord"; then
  pass "a v2# rebinding no longer counts as naming the v1 class"
else
  fail "a v2# rebinding was read as v1" \
"The file's own @context decides what its terms mean. $OUT"
fi
rm -rf "$DIR"

# ---------------------------------------------------------------------------
# 10. owl:deprecated FALSE IS NOT DEPRECATED. Scope matched on the predicate and
#     ignored the object, so a class explicitly un-deprecated -- or one that
#     inherited the triple from a copy-pasted sibling -- left scope silently and
#     was never required to have a published name. The gate went quiet on a live
#     record class, with no output at all.
# ---------------------------------------------------------------------------
echo ""
echo "10. A class marked owl:deprecated false is still in scope"

DIR="$(scratch)"
cat >> "$DIR/ontologies/core/v1/core.ttl" <<'TTL'

cascade:LiveProbeRecord a owl:Class, cascade:RecordClass ;
    rdfs:label "Live Probe Record"@en ;
    owl:deprecated false .
TTL
OUT="$("$PYTHON" "$CHECK" "$DIR" 2>&1)"
STATUS=$?
if [ $STATUS -ne 0 ] && printf '%s\n' "$OUT" | grep -q "cascade:LiveProbeRecord"; then
  pass "a live class saying so explicitly is still required to have a name"
else
  fail "owl:deprecated false was read as deprecated" \
"The object decides, not the predicate. $OUT"
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
