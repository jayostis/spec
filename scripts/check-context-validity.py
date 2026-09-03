#!/usr/bin/env python3
"""check-context-validity.py -- every published JSON-LD context must load.

Run from the spec repo root:
    python3 scripts/check-context-validity.py                  # all of contexts/
    python3 scripts/check-context-validity.py path/to/x.jsonld # specific files

WHY THIS EXISTS
---------------
A context file is a lookup table from short name to IRI, and every non-keyword
key in it IS a term definition. So a key whose value is prose is not a comment
that a processor skips -- it is a term definition whose IRI is a sentence, and a
conformant processor rejects THE WHOLE FILE over it. Not the one entry: all 716
terms in cascade.jsonld became unusable over six of them.

Three of the seven published contexts shipped that way, undetected, because
nothing had ever passed these files to a JSON-LD processor. json.load succeeds
on all seven -- they are valid JSON. Only expansion objects. See issue #48.

WHY NOT rdflib
--------------
rdflib is already pinned for this repository's other checks and it parses
JSON-LD, so it is the obvious thing to reach for. It is also the wrong thing:
rdflib's JSON-LD parser accepted all three broken files without complaint. A
check built on it would have sat green over the exact defect it exists to catch.
PyLD is pinned separately, in scripts/requirements.txt, for strictness.

NAMING THE CULPRIT
------------------
A processor reports the first error and stops, without saying which term caused
it -- "@context @id value must be an absolute IRI" over a 1,500-line file is a
poor place to start looking. So on failure this re-tests each term in isolation
against the file's own prefixes, and names every term that cannot stand alone.
Those prefixes are themselves checked first: a broken entry that happens to be
prefix-shaped would otherwise break every term it is tested against and be the
one entry never tested alone, naming 710 innocents and not the culprit.

An @-prefixed key is a candidate like any other. Only the eight keywords below
are configuration; every other @-key is either reserved-and-ignored (letters
only) or an error, and "keep the name, prepend an @" is the rescue this
repository's own docs single out as tempting. Skipping @-keys wholesale left
that one spelling -- the likeliest a contributor will write -- as the only
defect the check could detect but not name.

WHAT A FAILURE TO FETCH IS NOT
------------------------------
A context layer may be a remote IRI, and that is the one part of a file this
process does not hold. When retrieval fails the processor raises the same
JsonLdError it raises for a malformed term, so reporting every JsonLdError as
"invalid" blames the file for the network. Those are separated below and the
run exits 2 -- "nothing was verified" -- rather than 1.

That path is not exotic. scripts/requirements.txt pins neither requests nor
aiohttp, so PyLD has no default document loader at all: in the environment CI
builds, every remote layer fails to load on a machine that is perfectly online.
"""

import glob
import json
import sys

try:
    from pyld import jsonld
    from pyld.jsonld import JsonLdError
except ImportError:
    # Exit 2 with a message, never a traceback, and never a pass. CONTRIBUTING
    # promises this for every check here: a missing parser means the run
    # examined nothing, which must not be reported as success. The regression
    # suite guards its own import the same way.
    print("ERROR: cannot import pyld, so no context would be checked.\n"
          "       Install it:  python3 -m pip install -r scripts/requirements.txt",
          file=sys.stderr)
    sys.exit(2)

# Keys that carry configuration rather than a term definition.
CONTEXT_KEYWORDS = {
    "@version", "@vocab", "@base", "@language", "@direction", "@protected",
    "@import", "@propagate",
}

# JSON-LD error codes meaning the processor could not RETRIEVE something, as
# opposed to having read something wrong. The distinction is the whole point:
# one is a fact about the file, the other is a fact about this machine.
LOAD_FAILURE_CODES = {
    "loading document failed",
    "loading remote context failed",
    "no default document loader",
}


def load_failure(exc):
    """The innermost retrieval failure behind a JsonLdError, else None.

    PyLD wraps the cause, so the outermost error on an unreachable IRI is the
    generic "Dereferencing a URL did not result in a valid JSON-LD object";
    the chain below it carries the actual reason, which is the useful line.
    """
    found = None
    while exc is not None:
        if (isinstance(exc, JsonLdError)
                and getattr(exc, "code", None) in LOAD_FAILURE_CODES):
            found = exc
        exc = exc.__cause__
    return found


def install_caching_loader(inner=None):
    """Fetch each remote IRI at most once per run.

    culprits() re-expands the whole context once per candidate term, and PyLD
    resolves remote layers afresh on every expand() -- it caches nothing
    between calls. So narrowing a failure on a context with a remote layer
    refetched that IRI once per term: 710 times on a cascade-sized file.

    `inner` exists so the regression suite can count fetches without a socket.
    """
    if inner is None:
        inner = jsonld.get_document_loader()
    cache = {}

    def loader(url, options=None):
        if url not in cache:
            cache[url] = inner(url, options if options is not None else {})
        return cache[url]

    jsonld.set_document_loader(loader)


def is_prefix_entry(value):
    """A term usable as the prefix of a compact IRI elsewhere in the file."""
    return (isinstance(value, str)
            and ":" in value
            and (value.endswith("#") or value.endswith("/")))


def load_context(path):
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    # json.load returns whatever the file holds. A top-level array, string or
    # number has no .get, and the AttributeError that follows is not in the
    # except tuple in check(), so it escapes as a traceback and takes the
    # whole run down before the remaining files are checked.
    if not isinstance(doc, dict):
        raise ValueError(
            f"top level is {type(doc).__name__}, expected a JSON object")
    ctx = doc.get("@context")
    # A bare string is a remote context reference, as legal as the array form
    # and rejected here for months as "NOT A CONTEXT: @context is str" -- a
    # false statement about the file, reddening the gate on anything the
    # default contexts/**/*.jsonld glob reaches: a latest.jsonld alias, or any
    # example instance document dropped under contexts/.
    if not isinstance(ctx, (dict, list, str)):
        raise ValueError(f"@context is {type(ctx).__name__}, expected an "
                         "object, an array, or a remote context IRI")
    return ctx


def layers(ctx):
    """A context is one object, one remote IRI, OR an array of either.

    All three forms are legal, so nothing below may assume a bare object:
    treating another form as malformed would block a valid change on a file a
    conformant processor loads.
    """
    return ctx if isinstance(ctx, list) else [ctx]


def local_terms(ctx):
    """Term names defined inline, in order, across every object layer."""
    names = {}
    for layer in layers(ctx):
        if isinstance(layer, dict):
            for key in layer:
                if not key.startswith("@"):
                    names[key] = None
    return list(names)


def exercise(ctx):
    """Expand against the context, so every definition in it gets read.

    No term is USED in the document, and that is deliberate. A processor
    creates every term definition eagerly while processing the context, so a
    bare expansion already reads all of them. A document that instead assigns
    a value to every term reports the legal forms whose value shape is
    constrained: `{"@reverse": "..."}` rejects a plain string, so the usage is
    the syntax error, on a context a conformant processor accepts.
    """
    jsonld.expand({"@context": ctx, "@id": "urn:x:check-context-validity"})


def expands(ctx):
    """Whether a context processes cleanly, as a question rather than a raise.

    Used to establish that a base works BEFORE anything is appended to it and
    blamed for the failure.
    """
    try:
        exercise(ctx)
    except JsonLdError:
        return False
    return True


def failing_entries(base, candidates, skip=()):
    """Entries that fail when appended, one at a time, to a base that works.

    The base must already expand on its own. If it does not, every candidate
    fails and every one of them is reported innocent-of-nothing, so the caller
    checks the base first rather than emitting that list.

    Only the eight CONTEXT_KEYWORDS are exempt. Every OTHER @-prefixed key is
    tested like any term: a processor ignores an @-key only when what follows
    the @ is letters only, so "@comment_core" is a definition and fails exactly
    as "__comment_core" does. Skipping the whole @ namespace meant that one --
    the spelling a contributor reaches for first, since it looks like the fix
    -- was the single defect this check could detect and never name.
    """
    bad = []
    for layer in candidates:
        if not isinstance(layer, dict):
            continue
        for key, value in layer.items():
            if key in CONTEXT_KEYWORDS or key in skip:
                continue
            if not expands(base + [{key: value}]):
                bad.append((key, value))
    return bad


def culprits(ctx):
    """Which individual entries cannot be processed, given a base that works.

    The scaffold keeps the shape of the original: each object layer reduced to
    its keywords and prefixes, each remote layer left where it was. The entry
    under test is then appended as a final layer.

    THE SCAFFOLD IS TESTED FIRST, before any term, because it is the base every
    term test depends on. is_prefix_entry() admits any string containing ':'
    that ends in '#' or '/', so a BROKEN entry of that shape -- prose ending in
    a path, a real prefix with a stray space -- is copied into the scaffold.
    Blaming terms against it then accuses every innocent one while the entry
    itself, being in the scaffold, is the single key never tested alone: 710
    false culprits on cascade.jsonld with the real one named nowhere. So a
    scaffold that does not expand is the finding, and its own entries -- prefix
    entries very much included -- are what gets narrowed down.
    """
    scaffold = [
        {k: v for k, v in layer.items()
         if k in CONTEXT_KEYWORDS or is_prefix_entry(v)}
        if isinstance(layer, dict) else layer
        for layer in layers(ctx)
    ]

    if not expands(scaffold):
        # The fault is in the shared layer, so no term test below would mean
        # anything. Narrow it against the smallest base there is: the remote
        # layers, which contribute prefixes but no local definitions.
        remote = [layer for layer in layers(ctx) if not isinstance(layer, dict)]
        if not expands(remote):
            return []          # not even that loads; check() says so instead.
        return failing_entries(remote, scaffold)

    carried = {k for layer in scaffold if isinstance(layer, dict)
               for k in layer}
    return failing_entries(scaffold, layers(ctx), skip=carried)


def check(path):
    """Report on one file. Returns (problems, unchecked) -- see main()."""
    # The whole path, not the basename. The default glob deliberately reaches
    # past contexts/v1/, so contexts/v1/core.jsonld and contexts/v2/core.jsonld
    # are both opened -- and a basename label printed two lines both reading
    # "core.jsonld", one OK and one FAILED, with nothing saying which file to
    # open. The 22-wide field overflows gracefully, as it already does for any
    # basename longer than that.
    name = path.replace("\\", "/")

    try:
        ctx = load_context(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        # FileNotFoundError and IsADirectoryError are OSError, not
        # ValueError. A typo in a CI invocation must arrive as a FAILED line.
        # UnicodeDecodeError IS a ValueError, so a file that is not UTF-8 is
        # labelled NOT A CONTEXT rather than UNREADABLE.
        label = "UNREADABLE" if isinstance(exc, OSError) else "NOT A CONTEXT"
        print(f"{name:22s}    -- FAILED")
        print(f"      {label}: {exc}")
        return (1, 0)

    terms = local_terms(ctx)
    remote = [layer for layer in layers(ctx) if isinstance(layer, str)]

    # A context that defines nothing must not read as success. The whole class
    # of defect this file guards against is a check that examines nothing and
    # reports green.
    #
    # NOT_CHECKED rather than a problem, though, because {"@vocab": "..."} --
    # or an @import, or any keyword-only context -- defines no term and is
    # perfectly legal; PyLD accepts it. Exit 1 here would be this script
    # saying "a published context is invalid" about a file with nothing wrong
    # with it. Exit 2 says the true thing: nothing was examined. The
    # non-vacuity guard is unweakened -- it was never the exit CODE that
    # carried it, only that the run does not read as success.
    if not terms and not remote:
        print(f"{name:22s} {0:4d} terms -- NOT CHECKED")
        print("      EMPTY: no term definitions, so nothing was checked")
        return (0, 1)

    try:
        exercise(ctx)
    except JsonLdError as exc:
        unfetched = load_failure(exc)
        if unfetched is not None:
            # Not FAILED: the file has not been found wrong, it has not been
            # read in full. Narrowing to a culprit below would be meaningless
            # -- every candidate fails against a base that cannot load -- and
            # would refetch the same unreachable IRI once per term.
            url = (unfetched.details or {}).get("url", "the remote layer")
            print(f"{name:22s} {len(terms):4d} terms -- NOT CHECKED")
            print(f"      COULD NOT FETCH {url}")
            print(f"      {str(unfetched).splitlines()[0]}")
            print("      (a layer of this context is remote and was not "
                  "retrieved, so nothing here was verified -- this file is "
                  "not being called invalid)")
            return (0, 1)

        print(f"{name:22s} {len(terms):4d} terms -- FAILED")
        print(f"      {str(exc).splitlines()[0]}")
        bad = culprits(ctx)
        for key, value in bad:
            shown = value if isinstance(value, str) else json.dumps(value)
            if len(shown) > 60:
                shown = shown[:57] + "..."
            print(f"      INVALID TERM {key!r} -> {shown!r}")
        if not bad:
            print("      (no single term reproduces it; the fault is in the "
                  "context as a whole)")
        return (max(len(bad), 1), 0)

    print(f"{name:22s} {len(terms):4d} terms -- OK")
    return (0, 0)


def main():
    install_caching_loader()
    paths = sys.argv[1:]
    if not paths:
        # Every context under contexts/, not just contexts/v1/: the
        # workflow triggers on contexts/**, so a narrower glob leaves a
        # context outside v1/ running this job, passing it, and never opening
        # the file.
        paths = sorted(glob.glob("contexts/**/*.jsonld", recursive=True))
    if not paths:
        # Exit 2, not 1, and for the reason spelled out at the bottom of this
        # function: 1 is "a published context is invalid", 2 is "nothing was
        # verified". A run that matched no file has examined nothing, so
        # reporting 1 sends whoever reads the red run at contexts/ when the
        # fault is the working directory it was launched from.
        print("Error: no contexts found. Run from the spec repo root.",
              file=sys.stderr)
        return 2

    results = [check(p) for p in paths]
    problems = sum(r[0] for r in results)
    unchecked = sum(r[1] for r in results)

    print()
    # The summary goes to stderr and every line above it to stdout. Under CI
    # stdout is a pipe and block-buffered, so without this flush the summary
    # overtakes the report it summarises.
    sys.stdout.flush()
    if problems:
        print(f"FAILED: {problems} problem(s).", file=sys.stderr)
    if unchecked:
        print(f"NOT CHECKED: {unchecked} context(s) were not verified. Each "
              "says why on its own line above -- a remote layer that could "
              "not be retrieved, or no term definitions to check. They have "
              "NOT been found invalid.", file=sys.stderr)
    if problems:
        return 1
    # Exit 2, the same code a missing PyLD uses, and for the same reason: a run
    # that examined nothing must not report success. It is deliberately NOT
    # exit 1 -- these files have not been found invalid.
    if unchecked:
        return 2
    print(f"All {len(paths)} context(s) load in a strict JSON-LD processor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
