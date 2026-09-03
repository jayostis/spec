#!/usr/bin/env python3
"""check-context-coverage.py: a record class must have a published JSON name.

THE RULE

Every class carrying `a cascade:RecordClass`, in a vocabulary that publishes a
JSON-LD context, and not owl:deprecated, must be the value of a term in TWO
files: its own vocabulary's context, and the aggregate cascade.jsonld. A context
is exactly a name -> IRI mapping, so a record class absent from one of them has
no published JSON name there: a consumer writing or reading that record either
invents a name or cannot address the class.

BOTH, NOT EITHER. Pooling all seven files into one set would pass a class named
only in cascade.jsonld -- and a consumer loading coverage.jsonld alone, which is
the per-vocabulary context this repository publishes for exactly that purpose,
still could not address it. The two legs are checked separately and the failure
says which one is missing.

That is not hypothetical. jayostis/sdk-typescript maintained a hand-written
table of 39 record-type names and the class each is written as, and nothing
compared it to spec -- which is how InsurancePlan spent five releases pointing
at the deprecated clinical:CoverageRecord. Twelve record classes were named by
no context when this check was written (jayostis/spec#50).

WHAT THIS DOES NOT ASSERT, AND WHY IT MATTERS

It asserts a record class HAS a published name. It says nothing about whether
that name maps to the RIGHT IRI. A context resolving dateOfBirth to the wrong
predicate is valid JSON-LD, is named, and passes here. That is a different
question and an open one -- see jayostis/spec#46 and #47.

Nor does it assert the converse: a context may name plenty of things that are
not record classes (properties, value terms, external vocabulary), and should.

WHY NOT FOLD THIS INTO check-context-validity.py

That check asserts a context LOADS in a strict JSON-LD processor, which is a
property of the file alone -- it needs no ontology and it caught three files
that json.load accepted and a conformant processor refused (jayostis/spec#48).
This check needs the ontology graph and asserts a relationship BETWEEN two
artifacts. Merging them would mean a context could not be checked for validity
without a working ontology parse, and the narrower check is the one that has to
keep working when the vocabulary is mid-edit.

SCOPE

A class is in scope when contexts/v1/<vocabulary>.jsonld exists for the
vocabulary that declares it. The five draft vocabularies publish no context, so
their classes are out -- marked, examined by check-class-coverage.py, and simply
not yet named in JSON. Deprecated classes are out: a dead spelling does not need
a new published name, and the four that have one keep it.

Exit status: 0 if every in-scope class is named, 1 on any finding, and 1 if the
run examined no classes at all.

Usage:  python3 scripts/check-context-coverage.py [spec-root]

Requires: rdflib (see scripts/requirements.txt)
"""

import glob
import json
import os
import sys

try:
    from rdflib import Graph, RDF, URIRef
    from rdflib.namespace import OWL
except ImportError:  # pragma: no cover - environment guard
    sys.stderr.write(
        "ERROR: rdflib is not installed. This check parses Turtle and cannot\n"
        "       degrade to a text scan without becoming unsound.\n"
        "       Install it with:  python3 -m pip install -r scripts/requirements.txt\n"
    )
    sys.exit(2)

CASCADE_NS_PREFIX = "https://ns.cascadeprotocol.org/"
RECORD_CLASS_MARKER = URIRef(CASCADE_NS_PREFIX + "core/v1#RecordClass")

ONTOLOGY_GLOB = "ontologies/*/v1*/*.ttl"
CONTEXT_GLOB = "contexts/v1/*.jsonld"

# The one context that carries every vocabulary, so every record class owes it
# an entry as well as its own file.
AGGREGATE = "cascade"


def qname(uri):
    """Display form, derived from the IRI rather than tabulated.

    The namespace segment IS the prefix in every vocabulary but core, whose
    prefix is `cascade:` -- so the one irregular case is spelled out and the
    rest need no table to stay correct as vocabularies are added.
    """
    rest = str(uri)[len(CASCADE_NS_PREFIX):]
    vocab, _, local = rest.partition("#")
    segment = vocab.split("/")[0]
    return "%s:%s" % ("cascade" if segment == "core" else segment, local)


def vocabulary_dir(uri):
    """The ontologies/<dir> that declares this class, from its namespace."""
    rest = str(uri)[len(CASCADE_NS_PREFIX):]
    return rest.partition("#")[0].split("/")[0]


def load_ontology(root):
    graph, files = Graph(), []
    for path in sorted(glob.glob(os.path.join(root, ONTOLOGY_GLOB))):
        if path.endswith(".shapes.ttl"):
            continue
        graph.parse(path, format="turtle")
        files.append(path)
    if not files:
        sys.stderr.write(
            "ERROR: no ontology files matched %s under %s\n" % (ONTOLOGY_GLOB, root)
        )
        sys.exit(2)
    return graph, files


def context_names(root):
    """{context name: the IRIs it maps terms to}, absolute where resolvable.

    A term value is a compact IRI ("clinical:ImagingStudy") or an object with
    an "@id". Values naming a prefix the file does not declare are kept
    verbatim: they cannot match a Cascade class and dropping them would hide a
    malformed entry rather than report it.

    EACH CONTEXT IS RESOLVED AGAINST ITS OWN PREFIX DECLARATIONS, which are
    terms in the same @context object, and not against a table here. A table
    disagreed with the rest of the check: scope came from the filenames on disk,
    so publishing contexts/v1/genomics.jsonld put every marked genomics class in
    scope while `genomics:VariantRecord` resolved to nothing and matched no
    class -- the check would have failed for classes that were published
    correctly. Reading the file's own prefixes also means a context that
    redefined "health" to a /v2# namespace is read as v2, rather than silently
    credited with naming the v1 class.
    """
    by_context, files = {}, []
    for path in sorted(glob.glob(os.path.join(root, CONTEXT_GLOB))):
        with open(path, encoding="utf-8") as handle:
            context = json.load(handle).get("@context", {})
        files.append(path)

        # A term whose value is a bare namespace is a prefix declaration. The
        # trailing "#" or "/" is what distinguishes it from a term mapping.
        prefixes = {
            key: value for key, value in context.items()
            if not key.startswith("@") and isinstance(value, str)
            and (value.endswith("#") or value.endswith("/"))
        }

        iris = set()
        for key, value in context.items():
            if key.startswith("@"):
                continue
            target = value.get("@id") if isinstance(value, dict) else value
            if not isinstance(target, str):
                continue
            prefix, sep, local = target.partition(":")
            if sep and prefix in prefixes:
                iris.add(prefixes[prefix] + local)
            else:
                iris.add(target)
        by_context[os.path.splitext(os.path.basename(path))[0]] = iris

    if not files:
        sys.stderr.write(
            "ERROR: no context files matched %s under %s\n" % (CONTEXT_GLOB, root)
        )
        sys.exit(2)
    return by_context, files


def main():
    args = [a for a in sys.argv[1:]]
    root = args[0] if args else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ".."
    )
    root = os.path.abspath(root)

    ontology, onto_files = load_ontology(root)
    by_context, ctx_files = context_names(root)

    # The OBJECT decides, not the predicate: `owl:deprecated false` is a live
    # class saying so. Matching on the predicate alone dropped it out of scope
    # and the gate went quiet on a record class with no output at all.
    deprecated = {
        s for s, _, o in ontology.triples((None, OWL.deprecated, None))
        if bool(o)
    }
    marked = {
        c for c in ontology.subjects(RDF.type, RECORD_CLASS_MARKER)
        if isinstance(c, URIRef) and str(c).startswith(CASCADE_NS_PREFIX)
        and c != RECORD_CLASS_MARKER
    }

    publishes = set(by_context)
    in_scope = sorted(
        (c for c in marked
         if vocabulary_dir(c) in publishes and c not in deprecated),
        key=qname,
    )
    aggregate = by_context.get(AGGREGATE)

    print("Record-class context coverage check")
    print("  root:              %s" % root)
    print("  ontologies parsed: %d" % len(onto_files))
    print("  contexts parsed:   %d  (%d distinct IRIs mapped)"
          % (len(ctx_files), len(set().union(*by_context.values()))))
    print("  marked classes:    %d  (a cascade:RecordClass)" % len(marked))
    print("  in scope:          %d  (vocabulary publishes a context, not deprecated)"
          % len(in_scope))
    print("  required in:       its own vocabulary's context%s"
          % (" and %s.jsonld" % AGGREGATE if aggregate is not None else
             " only (%s.jsonld is not published)" % AGGREGATE))
    print()

    if not in_scope:
        print("EMPTY: no marked class is in a vocabulary that publishes a context.")
        print("RESULT: FAIL")
        return 1

    findings = []
    for cls in in_scope:
        own = vocabulary_dir(cls)
        missing = [
            "%s.jsonld" % name for name, iris in (
                (own, by_context[own]),
                (AGGREGATE, aggregate),
            )
            if iris is not None and str(cls) not in iris
        ]
        if missing:
            findings.append((cls, missing))

    if findings:
        print("FAIL  %d record class(es) are not published where the rule requires:"
              % len(findings))
        for cls, missing in findings:
            print("        %-42s missing from %s" % (qname(cls), ", ".join(missing)))
        print()
        print("      A JSON-LD context is a name -> IRI mapping, so a record class")
        print("      absent from one has no published JSON name THERE. A consumer")
        print("      either invents one -- which is how two spellings of a class end")
        print("      up in circulation -- or cannot address it at all.")
        print()
        print("      Publish the class in its own vocabulary's context AND in")
        print("      %s.jsonld, which is the convention the great majority of"
              % AGGREGATE)
        print("      %s.jsonld's terms already follow. Where a local name is"
              % AGGREGATE)
        print("      already taken in the aggregate by another vocabulary, give it a")
        print("      distinct key: the term key is free, the IRI it maps to is not.")
        print()
        print("RESULT: FAIL")
        return 1

    print("RESULT: PASS, %d in-scope record class(es) all have a published name."
          % len(in_scope))
    return 0


if __name__ == "__main__":
    sys.exit(main())
