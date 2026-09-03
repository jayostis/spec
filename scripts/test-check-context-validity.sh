#!/bin/sh
# test-check-context-validity.sh
#
# Regression suite for check-context-validity.py.
#
# The defect under test: a section-header comment written as an ordinary context
# term -- "__comment_core": "=== Core Vocabulary ===" -- is not a comment. Every
# non-keyword key in a context IS a term definition, so its value must be an
# IRI, and prose is not one. A conformant processor rejects the entire file over
# it. Three of the seven published contexts shipped that way. See issue #48.
#
# Every assertion below is paired with a NEGATIVE CONTROL: a scratch copy of a
# real context with one defect deliberately introduced, which the check must
# catch and must name. A check that has only ever been observed passing is not
# evidence that it can fail -- and a validity check that cannot fail would be
# this same defect one level up.
#
# Control 6 is the one to read before changing the dependency. rdflib is already
# pinned for this repository's other checks and it parses JSON-LD, so it is the
# obvious thing to reach for and it is the wrong thing: it accepts the broken
# file. That control fails if anyone swaps the strict processor out for it.
#
# Usage: ./scripts/test-check-context-validity.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEC_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$SCRIPT_DIR/check-context-validity.py"
PYTHON="${PYTHON:-python3}"

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); echo "  PASS  $1"; }
fail() { FAILED=$((FAILED + 1)); echo "  FAIL  $1"; echo "        $2"; }

# A missing processor is a hard failure, never a skip. Skipping the suite
# because a dependency is absent reports green while testing nothing, which is
# the exact class of defect this file guards against.
if ! "$PYTHON" -c "import pyld" 2>/dev/null; then
  echo "ERROR: $PYTHON cannot import pyld, so this suite would test nothing."
  echo "       Install it:  $PYTHON -m pip install -r scripts/requirements.txt"
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# coverage.jsonld is the smallest context that loads cleanly today, so a
# failure in a control below is the injected defect and not pre-existing noise.
SUBJECT="$SPEC_ROOT/contexts/v1/coverage.jsonld"

# fixture_ready <status> <what> -- a fixture that was not built is not a
# control that passed. Without this the scratch file is simply never written
# and the control below crashes out of open() with a Python traceback.
fixture_ready() {
  if [ "$1" -ne 0 ]; then
    echo "ERROR: could not build the fixture for '$2', so the controls below"
    echo "       would test nothing. Stopping."
    exit 2
  fi
}

# inject <src> <dst> <key> <value> -- add one term to a context's @context.
inject() {
  "$PYTHON" - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
src, dst, key, value = sys.argv[1:5]
with open(src, encoding="utf-8") as fh:
    doc = json.load(fh)
assert key not in doc["@context"], "fixture already defines %r" % key
doc["@context"][key] = value
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
PY
  fixture_ready $? "$3"
}

# inject_json <src> <dst> <key> <json> -- as inject, but the value is parsed as
# JSON, so the term can be given an expanded definition object.
inject_json() {
  "$PYTHON" - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
src, dst, key, value = sys.argv[1:5]
with open(src, encoding="utf-8") as fh:
    doc = json.load(fh)
assert key not in doc["@context"], "fixture already defines %r" % key
doc["@context"][key] = json.loads(value)
with open(dst, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
PY
  fixture_ready $? "$3"
}

# split <src> <dst> [extra-json] -- rewrite a context into the ARRAY form,
# prefixes in the first layer and everything else in the second, optionally
# merging one more object into the second layer.
split() {
  "$PYTHON" - "$1" "$2" "${3:-null}" <<'PY'
import json, sys
src, dst, extra = sys.argv[1:4]
with open(src, encoding="utf-8") as fh:
    ctx = json.load(fh)["@context"]
prefixes = {k: v for k, v in ctx.items()
            if isinstance(v, str) and (v.endswith("#") or v.endswith("/"))}
rest = {k: v for k, v in ctx.items() if k not in prefixes}
rest.update(json.loads(extra) or {})
with open(dst, "w", encoding="utf-8") as fh:
    json.dump({"@context": [prefixes, rest]}, fh, indent=2, ensure_ascii=False)
PY
  fixture_ready $? "array-valued @context"
}

# remote_split <src> <dst> <iri> [extra-json] -- rewrite a context into the
# ARRAY form with a REMOTE first layer: [ "<iri>", { ...everything... } ].
# Legal JSON-LD, and the one layer this process does not hold a copy of.
remote_split() {
  "$PYTHON" - "$1" "$2" "$3" "${4:-null}" <<'PY'
import json, sys
src, dst, iri, extra = sys.argv[1:5]
with open(src, encoding="utf-8") as fh:
    ctx = json.load(fh)["@context"]
ctx = dict(ctx)
ctx.update(json.loads(extra) or {})
with open(dst, "w", encoding="utf-8") as fh:
    json.dump({"@context": [iri, ctx]}, fh, indent=2, ensure_ascii=False)
PY
  fixture_ready $? "remote-layer @context"
}

# An IRI nothing can dereference, chosen so the controls below stay offline and
# fast: port 1 on the loopback interface refuses immediately, with no DNS
# lookup and no timeout. A control that reaches the network would fail in the
# same circumstances it exists to describe.
UNREACHABLE="http://127.0.0.1:1/base.jsonld"

echo "check-context-validity.py regression suite"
echo ""

# -- 1. The repository itself passes -----------------------------------------
# The outer loop. Red until the eight prose terms are gone from contexts/v1/.
if (cd "$SPEC_ROOT" && "$PYTHON" "$CHECK" >/dev/null 2>&1); then
  pass "every context in this repository loads in a strict processor"
else
  (cd "$SPEC_ROOT" && "$PYTHON" "$CHECK" 2>&1 | tail -20)
  fail "every context in this repository loads in a strict processor" \
       "the check reports a problem against unmodified sources"
fi

# -- 2. Negative control: a prose-valued term --------------------------------
# The exact defect that shipped, in the exact spelling it shipped in.
inject "$SUBJECT" "$WORK/prose.jsonld" "__comment_section" "=== Section ==="
OUT="$("$PYTHON" "$CHECK" "$WORK/prose.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "INVALID TERM '__comment_section'"; then
  pass "a term whose value is prose is caught and named"
else
  fail "a term whose value is prose is caught and named" \
       "check did not fail, or did not name the term: $OUT"
fi

# -- 3. Negative control: an @-prefixed key is not automatically ignored ------
# A processor ignores an @-prefixed key only when what follows the @ is LETTERS
# ONLY. "@comment_core" is the obvious way to rescue the old names and it fails
# exactly as the original did, which is why deletion was chosen over re-keying.
#
# The key must be NAMED, not merely counted. This control once asserted only a
# non-zero exit, and passed while the check printed "(no single term reproduces
# it; the fault is in the context as a whole)" -- false, and on a 1,500-line
# cascade.jsonld precisely the un-navigable first-error message the NAMING THE
# CULPRIT docstring says it replaces. Since "keep the name, prepend an @" is
# the rescue CHANGELOG.md and CLAUDE.md single out, it is the failure a
# contributor is most likely to meet, and the one that named nobody.
inject "$SUBJECT" "$WORK/atunderscore.jsonld" "@comment_section" "=== Section ==="
OUT="$("$PYTHON" "$CHECK" "$WORK/atunderscore.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "INVALID TERM '@comment_section'"; then
  pass "an @-key with an underscore is still rejected, and named"
else
  fail "an @-key with an underscore is still rejected, and named" \
       "check passed it, or failed without naming the key: $OUT"
fi

# -- 4. Positive control: a letters-only @-key IS ignored ---------------------
# The other half of control 3. Without this the suite would be satisfied by a
# check that simply rejected every @-prefixed key.
inject "$SUBJECT" "$WORK/atletters.jsonld" "@commentSection" "=== Section ==="
OUT="$("$PYTHON" "$CHECK" "$WORK/atletters.jsonld" 2>&1)"
if [ $? -eq 0 ]; then
  pass "a letters-only @-key is ignored by the processor and passes"
else
  fail "a letters-only @-key is ignored by the processor and passes" \
       "check rejected a context a processor accepts: $OUT"
fi

# -- 5. Non-vacuity: nothing to check must not read as success ----------------
cat > "$WORK/empty.jsonld" <<'JSON'
{ "@context": {} }
JSON
OUT="$("$PYTHON" "$CHECK" "$WORK/empty.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "EMPTY"; then
  pass "a context defining no terms is reported as examining nothing"
else
  fail "a context defining no terms is reported as examining nothing" \
       "expected a failure naming EMPTY: $OUT"
fi

# -- 6. The processor must be a strict one -----------------------------------
# rdflib parses JSON-LD and accepts the broken file. If this check is ever
# rewritten against it -- the tempting move, since rdflib is already pinned --
# every control above still passes except this one.
if "$PYTHON" -c "import rdflib" 2>/dev/null; then
  LENIENT="$("$PYTHON" - "$WORK/prose.jsonld" <<'PY'
import json, sys
from rdflib import Graph
with open(sys.argv[1], encoding="utf-8") as fh:
    ctx = json.load(fh)["@context"]
doc = json.dumps({"@context": ctx, "@id": "urn:x", "coverageCoverageType": "v"})
try:
    Graph().parse(data=doc, format="json-ld")
    print("accepted")
except Exception:
    print("rejected")
PY
)"
  if [ "$LENIENT" = "accepted" ]; then
    pass "rdflib accepts the broken context, so the check is not using it"
  else
    fail "rdflib accepts the broken context, so the check is not using it" \
         "rdflib rejected it too, so control 6 no longer distinguishes anything"
  fi
else
  fail "rdflib accepts the broken context, so the check is not using it" \
       "rdflib is not importable, so this control tested nothing"
fi

# -- 7. Positive control: a legal @reverse term definition -------------------
# The check must read every definition without USING any term. A document that
# assigns a value to every term instead rejects this context: a @reverse term's
# value may not be a plain string, so the usage itself is the syntax error, on
# a context a conformant processor accepts.
inject_json "$SUBJECT" "$WORK/reverse.jsonld" "employedBy"             '{"@reverse": "coverage:coverageStatus"}'
OUT="$("$PYTHON" "$CHECK" "$WORK/reverse.jsonld" 2>&1)"
if [ $? -eq 0 ]; then
  pass "a legal @reverse term definition is accepted"
else
  fail "a legal @reverse term definition is accepted"        "check rejected a context a processor accepts: $OUT"
fi

# -- 8. Positive control: an array-valued @context ---------------------------
# "@context": [ {...}, {...} ] is legal JSON-LD. An object-only loader reports
# the file as NOT A CONTEXT and blocks a valid change.
split "$SUBJECT" "$WORK/array.jsonld"
OUT="$("$PYTHON" "$CHECK" "$WORK/array.jsonld" 2>&1)"
if [ $? -eq 0 ]; then
  pass "an array-valued @context is accepted"
else
  fail "an array-valued @context is accepted"        "check rejected a legal context form: $OUT"
fi

# -- 9. Negative control: array support must not be hollow -------------------
# The cheap way to stop rejecting arrays is to stop looking inside them. This
# is control 2's defect, in the second layer of an array.
split "$SUBJECT" "$WORK/arrayprose.jsonld" '{"__comment_section": "=== Section ==="}'
OUT="$("$PYTHON" "$CHECK" "$WORK/arrayprose.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "INVALID TERM '__comment_section'"; then
  pass "a prose term inside an array-valued @context is caught and named"
else
  fail "a prose term inside an array-valued @context is caught and named"        "check did not fail, or did not name the term: $OUT"
fi

# -- 10. A path that cannot be read is a FAILED line, not a traceback --------
# FileNotFoundError, IsADirectoryError and UnicodeDecodeError are not
# ValueError. A typo in a CI invocation must produce a diagnostic.
OUT="$("$PYTHON" "$CHECK" "$WORK/no-such-file.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "FAILED"    && ! echo "$OUT" | grep -q "Traceback"; then
  pass "an unreadable path is reported, not raised as a traceback"
else
  fail "an unreadable path is reported, not raised as a traceback"        "expected a FAILED line and no traceback: $OUT"
fi

# -- 11. Negative control: a broken entry that is PREFIX-SHAPED --------------
# is_prefix_entry() copies any string containing ':' and ending in '#' or '/'
# into the scaffold that every per-term test is run against. A BROKEN entry of
# that shape -- prose ending in a path, a real prefix with a stray space --
# therefore poisons the base: every innocent term fails against it, and the
# entry itself, being in the scaffold, is the one key never tested alone. On
# cascade.jsonld that was 710 false accusations with the real culprit named
# nowhere, which is strictly worse than the raw first-error message the
# NAMING THE CULPRIT docstring says it replaces.
inject "$SUBJECT" "$WORK/prefixprose.jsonld" "__comment_x" "=== Coverage terms, see: docs/schemas/"
OUT="$("$PYTHON" "$CHECK" "$WORK/prefixprose.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "INVALID TERM '__comment_x'" && ! echo "$OUT" | grep -q "INVALID TERM 'InsurancePlan'"; then
  pass "a prefix-shaped broken entry is named, and no innocent term accused"
else
  fail "a prefix-shaped broken entry is named, and no innocent term accused" \
       "expected '__comment_x' named and 'InsurancePlan' not: $OUT"
fi

# -- 12. A .jsonld whose top level is not an object is a FAILED line ---------
# doc.get("@context") assumes json.load returned a dict. AttributeError is not
# in the except tuple in check(), so a top-level array, string or number
# escaped as a traceback and took the whole run down before the remaining
# files were checked -- the thing control 10 exists to prevent, one printf
# away from any hand-written file.
printf '[]' > "$WORK/toplevel-array.jsonld"
OUT="$("$PYTHON" "$CHECK" "$WORK/toplevel-array.jsonld" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "FAILED" && ! echo "$OUT" | grep -q "Traceback"; then
  pass "a top-level JSON array is reported, not raised as a traceback"
else
  fail "a top-level JSON array is reported, not raised as a traceback" \
       "expected a FAILED line and no traceback: $OUT"
fi

# -- 13. The default glob must cover everything the workflow triggers on -----
# .github/workflows/contexts.yml fires on any change under contexts/**, so a
# PR adding contexts/v2/core.jsonld runs this job. A default glob pinned to
# contexts/v1/ never opens the new file, the job passes, and the run still
# prints "All N context(s) load" -- the same vacuous pass control 5 exists to
# prevent, one directory up.
mkdir -p "$WORK/root/contexts/v1" "$WORK/root/contexts/v2"
cp "$SUBJECT" "$WORK/root/contexts/v1/ok.jsonld"
inject "$SUBJECT" "$WORK/root/contexts/v2/broken.jsonld" "__comment_section" "=== Section ==="
OUT="$(cd "$WORK/root" && "$PYTHON" "$CHECK" 2>&1)"
if [ $? -ne 0 ] && echo "$OUT" | grep -q "INVALID TERM '__comment_section'"; then
  pass "the default glob reaches a context outside contexts/v1/"
else
  fail "the default glob reaches a context outside contexts/v1/" \
       "a broken contexts/v2/ file was never opened: $OUT"
fi

# -- 14. A missing processor exits 2 with a message, never a traceback --------
# CONTRIBUTING promises this for every check in this repository, and the reason
# is the same one behind control 5: a run that examined nothing must not be
# reported as success, and a traceback is not a diagnosis. The stub shadows the
# real package on PYTHONPATH and raises on import.
mkdir -p "$WORK/nopyld"
echo 'raise ImportError("blocked by test-check-context-validity.sh")' \
  > "$WORK/nopyld/pyld.py"
OUT="$(PYTHONPATH="$WORK/nopyld" "$PYTHON" "$CHECK" "$SUBJECT" 2>&1)"
STATUS=$?
if [ "$STATUS" -eq 2 ] \
   && echo "$OUT" | grep -q "cannot import pyld" \
   && ! echo "$OUT" | grep -q "Traceback"; then
  pass "a missing PyLD exits 2 with a message, not a traceback"
else
  fail "a missing PyLD exits 2 with a message, not a traceback" \
       "expected exit 2 and a diagnostic, got exit $STATUS: $OUT"
fi

# -- 15. Positive control: a string-valued @context is a legal context -------
# "@context": "https://…/cascade.jsonld" is a remote context reference, as
# legal as the array form control 8 covers, and load_context() rejected it with
# NOT A CONTEXT: @context is str. That is a false statement about the file, and
# it reddens the gate on anything the default contexts/**/*.jsonld glob picks
# up -- a contexts/v1/latest.jsonld alias, or any example instance document
# dropped under contexts/.
#
# What happens NEXT is control 16's subject, not this one's: the reference
# still cannot be dereferenced here. This asserts only that the file is no
# longer turned away for the TYPE of its @context.
printf '{ "@context": "%s" }' "$UNREACHABLE" > "$WORK/stringctx.jsonld"
OUT="$("$PYTHON" "$CHECK" "$WORK/stringctx.jsonld" 2>&1)"
if ! echo "$OUT" | grep -q "NOT A CONTEXT"; then
  pass "a string-valued @context is not rejected as malformed"
else
  fail "a string-valued @context is not rejected as malformed" \
       "check called a legal remote context reference malformed: $OUT"
fi

# -- 16. A remote layer that cannot be fetched is NOT the file being invalid --
# layers() goes out of its way to support ["https://…/base.jsonld", {…}], and
# exercise() hands that IRI to PyLD's document loader. Every failure to
# retrieve it used to arrive as a JsonLdError like any other, so the check
# printed the file as FAILED and added "(no single term reproduces it; the
# fault is in the context as a whole)" -- blaming the file for the network.
#
# This is not a rare path. scripts/requirements.txt pins neither requests nor
# aiohttp, so PyLD has NO default document loader at all: in the environment CI
# builds and CONTRIBUTING tells contributors to build, EVERY remote layer fails
# this way, on a machine that is perfectly online.
#
# The distinct status matters more than the exit code: exit 2 is this
# repository's "the run examined nothing", the same code control 14 asserts for
# a missing processor, and it must not be exit 1's "your file is wrong".
printf '{ "@context": ["%s", { "a": "http://example.org/a" }] }' "$UNREACHABLE" \
  > "$WORK/remote.jsonld"
OUT="$("$PYTHON" "$CHECK" "$WORK/remote.jsonld" 2>&1)"
STATUS=$?
if [ "$STATUS" -eq 2 ] \
   && echo "$OUT" | grep -q "COULD NOT FETCH" \
   && ! echo "$OUT" | grep -q "no single term reproduces it" \
   && ! echo "$OUT" | grep -q "INVALID TERM"; then
  pass "an unfetchable remote layer is reported as unfetched, not as invalid"
else
  fail "an unfetchable remote layer is reported as unfetched, not as invalid" \
       "expected exit 2 and COULD NOT FETCH with nothing blamed, got exit $STATUS: $OUT"
fi

# -- 17. A remote layer is fetched once per RUN, not once per candidate term --
# culprits() re-expands the whole context once per candidate term, and PyLD
# resolves remote layers afresh on every expand() -- it caches nothing between
# calls (measured: 5 expands, 5 fetches). So a failing context with a remote
# layer refetched that IRI once per term: 710 times on a cascade-sized file.
#
# The loader is injected rather than served, so this control needs no socket
# and no port: the fake counts what a real one would fetch. The fixture must
# FAIL, since a context that expands cleanly never reaches culprits() and would
# fetch once however the loader behaves.
remote_split "$SUBJECT" "$WORK/remotecul.jsonld" "http://x.example/base.jsonld" \
  '{"__comment_section": "=== Section ==="}'
# The counter goes in a file rather than a heredoc inside a command
# substitution: that construct is the one shape in this suite that has been
# seen to misparse on a stricter /bin/sh, and a control that dies on its own
# quoting proves nothing about the check.
cat > "$WORK/countfetch.py" <<'PY'
import importlib.util, sys

spec = importlib.util.spec_from_file_location("ccv", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

calls = []


def fake(url, options=None):
    calls.append(url)
    return {"contextUrl": None, "documentUrl": url,
            "document": {"@context": {"remotebase": "http://example.org/remote#"}}}


mod.install_caching_loader(fake)
mod.check(sys.argv[2])

# To a file, not to a stream: check() writes its own diagnostics to both, and
# a count fished back out of that with tail is a control that can pass on the
# wrong line.
with open(sys.argv[3], "w", encoding="utf-8") as fh:
    fh.write("%d" % len(calls))
PY
rm -f "$WORK/count.txt"
"$PYTHON" "$WORK/countfetch.py" "$CHECK" "$WORK/remotecul.jsonld" "$WORK/count.txt" \
  >/dev/null 2>&1
COUNT="$(tr -d '\r\n' < "$WORK/count.txt" 2>/dev/null)"
if [ "$COUNT" = "1" ]; then
  pass "a remote layer is fetched once per run, not once per candidate term"
else
  fail "a remote layer is fetched once per run, not once per candidate term" \
       "expected 1 fetch while narrowing the culprit, got: $COUNT"
fi

# -- 18. Two contexts with the same basename must be told apart --------------
# Control 13 widened the default glob past contexts/v1/ precisely so a
# contexts/v2/core.jsonld is opened -- and then check() labelled its line with
# the BASENAME, so the run printed two lines both reading "core.jsonld", one OK
# and one FAILED, with nothing saying which file to open. The ambiguity arrives
# in exactly the case the widening was for.
mkdir -p "$WORK/dup/contexts/v1" "$WORK/dup/contexts/v2"
cp "$SUBJECT" "$WORK/dup/contexts/v1/core.jsonld"
inject "$SUBJECT" "$WORK/dup/contexts/v2/core.jsonld" "__comment_section" "=== Section ==="
OUT="$(cd "$WORK/dup" && "$PYTHON" "$CHECK" 2>&1)"
if [ $? -ne 0 ] \
   && echo "$OUT" | grep -q "contexts/v1/core.jsonld" \
   && echo "$OUT" | grep -q "contexts/v2/core.jsonld"; then
  pass "same-named contexts in different directories are reported by path"
else
  fail "same-named contexts in different directories are reported by path" \
       "expected both paths named, not two bare 'core.jsonld' lines: $OUT"
fi

echo ""
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ] || exit 1
