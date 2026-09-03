#!/usr/bin/env python3
"""check-context-validity.py -- every published JSON-LD context must load.

Run from the spec repo root:
    python3 scripts/check-context-validity.py                  # all of contexts/v1/
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
"""

import glob
import json
import sys

from pyld import jsonld
from pyld.jsonld import JsonLdError

# Keys that carry configuration rather than a term definition.
CONTEXT_KEYWORDS = {
    "@version", "@vocab", "@base", "@language", "@direction", "@protected",
    "@import", "@propagate",
}


def is_prefix_entry(value):
    """A term usable as the prefix of a compact IRI elsewhere in the file."""
    return (isinstance(value, str)
            and ":" in value
            and (value.endswith("#") or value.endswith("/")))


def load_context(path):
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    ctx = doc.get("@context")
    if not isinstance(ctx, (dict, list)):
        raise ValueError(
            f"@context is {type(ctx).__name__}, expected an object or an array")
    return ctx


def layers(ctx):
    """A context is one object OR an array of objects and remote IRIs.

    Both forms are legal, so nothing below may assume a bare object: treating
    the array form as malformed would block a valid change on a file a
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


def culprits(ctx):
    """Which individual terms cannot be processed, given the file's prefixes.

    The scaffold keeps the shape of the original: each object layer reduced to
    its keywords and prefixes, each remote layer left where it was. The term
    under test is then appended as a final layer.
    """
    scaffold = [
        {k: v for k, v in layer.items()
         if k in CONTEXT_KEYWORDS or is_prefix_entry(v)}
        if isinstance(layer, dict) else layer
        for layer in layers(ctx)
    ]
    carried = {k for layer in scaffold if isinstance(layer, dict)
               for k in layer}

    bad = []
    for layer in layers(ctx):
        if not isinstance(layer, dict):
            continue
        for key, value in layer.items():
            if key.startswith("@") or key in carried:
                continue
            try:
                jsonld.expand({"@context": scaffold + [{key: value}],
                               "@id": "urn:x:check-context-validity"})
            except JsonLdError as exc:
                bad.append((key, value, str(exc).splitlines()[0]))
    return bad


def check(path):
    name = path.replace("\\", "/").rsplit("/", 1)[-1]

    try:
        ctx = load_context(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        # FileNotFoundError, IsADirectoryError and UnicodeDecodeError are not
        # ValueError. A typo in a CI invocation must arrive as a FAILED line.
        label = "UNREADABLE" if isinstance(exc, OSError) else "NOT A CONTEXT"
        print(f"{name:22s}    -- FAILED")
        print(f"      {label}: {exc}", file=sys.stderr)
        return 1

    terms = local_terms(ctx)
    remote = [layer for layer in layers(ctx) if isinstance(layer, str)]

    # A context that defines nothing must not read as success. The whole class
    # of defect this file guards against is a check that examines nothing and
    # reports green.
    if not terms and not remote:
        print(f"{name:22s} {0:4d} terms -- FAILED")
        print("      EMPTY: no term definitions, so nothing was checked",
              file=sys.stderr)
        return 1

    try:
        exercise(ctx)
    except JsonLdError as exc:
        print(f"{name:22s} {len(terms):4d} terms -- FAILED")
        print(f"      {str(exc).splitlines()[0]}", file=sys.stderr)
        bad = culprits(ctx)
        for key, value, _ in bad:
            shown = value if isinstance(value, str) else json.dumps(value)
            if len(shown) > 60:
                shown = shown[:57] + "..."
            print(f"      INVALID TERM {key!r} -> {shown!r}", file=sys.stderr)
        if not bad:
            print("      (no single term reproduces it; the fault is in the "
                  "context as a whole)", file=sys.stderr)
        return max(len(bad), 1)

    print(f"{name:22s} {len(terms):4d} terms -- OK")
    return 0


def main():
    paths = sys.argv[1:]
    if not paths:
        paths = sorted(glob.glob("contexts/v1/*.jsonld"))
    if not paths:
        print("Error: no contexts found. Run from the spec repo root.",
              file=sys.stderr)
        return 1

    problems = sum(check(p) for p in paths)
    print()
    if problems:
        print(f"FAILED: {problems} problem(s).", file=sys.stderr)
        return 1
    print(f"All {len(paths)} context(s) load in a strict JSON-LD processor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
