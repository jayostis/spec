#!/usr/bin/env python3
"""check-context-coverage.py: a record class must have a published JSON name.

THE RULE

Every class carrying `a cascade:RecordClass`, in a vocabulary that publishes a
JSON-LD context, and not owl:deprecated, must be the value of at least one term
in contexts/v1/. A context is exactly a name -> IRI mapping, so a record class
absent from all seven has no published JSON name at all: a consumer writing or
reading that record either invents a name or cannot address the class.

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

# Prefix a context uses for each vocabulary, so a term value like
# "clinical:ImagingStudy" can be resolved to an absolute IRI.
PREFIX_SEGMENT = {
    "cascade": "core/v1#",
    "health": "health/v1#",
    "clinical": "clinical/v1#",
    "coverage": "coverage/v1#",
    "checkup": "checkup/v1#",
    "pots": "pots/v1#",
}
SEGMENT_PREFIX = {v: k for k, v in PREFIX_SEGMENT.items()}


def qname(uri):
    rest = str(uri)[len(CASCADE_NS_PREFIX):]
    vocab, _, local = rest.partition("#")
    return "%s:%s" % (SEGMENT_PREFIX.get(vocab + "#", vocab), local)


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


def named_iris(root):
    """Every IRI any context maps a term to, absolute where resolvable.

    A term value is a compact IRI ("clinical:ImagingStudy") or an object with
    an "@id". Values naming a prefix this repository does not own are kept
    verbatim: they cannot match a Cascade class and dropping them would hide a
    malformed entry rather than report it.
    """
    iris, files = set(), []
    for path in sorted(glob.glob(os.path.join(root, CONTEXT_GLOB))):
        with open(path, encoding="utf-8") as handle:
            context = json.load(handle).get("@context", {})
        files.append(path)
        for key, value in context.items():
            if key.startswith("@"):
                continue
            target = value.get("@id") if isinstance(value, dict) else value
            if not isinstance(target, str):
                continue
            prefix, sep, local = target.partition(":")
            if sep and prefix in PREFIX_SEGMENT:
                iris.add(CASCADE_NS_PREFIX + PREFIX_SEGMENT[prefix] + local)
            else:
                iris.add(target)
    if not files:
        sys.stderr.write(
            "ERROR: no context files matched %s under %s\n" % (CONTEXT_GLOB, root)
        )
        sys.exit(2)
    return iris, files


def main():
    args = [a for a in sys.argv[1:]]
    root = args[0] if args else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ".."
    )
    root = os.path.abspath(root)

    ontology, onto_files = load_ontology(root)
    iris, ctx_files = named_iris(root)

    deprecated = set(ontology.subjects(OWL.deprecated, None))
    marked = {
        c for c in ontology.subjects(RDF.type, RECORD_CLASS_MARKER)
        if isinstance(c, URIRef) and str(c).startswith(CASCADE_NS_PREFIX)
        and c != RECORD_CLASS_MARKER
    }

    publishes = {
        os.path.splitext(os.path.basename(p))[0] for p in ctx_files
    }
    in_scope = sorted(
        (c for c in marked
         if vocabulary_dir(c) in publishes and c not in deprecated),
        key=qname,
    )

    print("Record-class context coverage check")
    print("  root:              %s" % root)
    print("  ontologies parsed: %d" % len(onto_files))
    print("  contexts parsed:   %d  (%d distinct IRIs mapped)"
          % (len(ctx_files), len(iris)))
    print("  marked classes:    %d  (a cascade:RecordClass)" % len(marked))
    print("  in scope:          %d  (vocabulary publishes a context, not deprecated)"
          % len(in_scope))
    print()

    if not in_scope:
        print("EMPTY: no marked class is in a vocabulary that publishes a context.")
        print("RESULT: FAIL")
        return 1

    unnamed = [c for c in in_scope if str(c) not in iris]

    if unnamed:
        print("FAIL  %d record class(es) are named by no context:" % len(unnamed))
        for cls in unnamed:
            print("        %s" % qname(cls))
        print()
        print("      A JSON-LD context is a name -> IRI mapping, so a record class")
        print("      absent from all of contexts/v1/ has no published JSON name. A")
        print("      consumer either invents one -- which is how two spellings of a")
        print("      class end up in circulation -- or cannot address it at all.")
        print()
        print("      Publish the class in its own vocabulary's context AND in")
        print("      cascade.jsonld, which is the convention the great majority of")
        print("      cascade.jsonld's terms already follow.")
        print()
        print("RESULT: FAIL")
        return 1

    print("RESULT: PASS, %d in-scope record class(es) all have a published name."
          % len(in_scope))
    return 0


if __name__ == "__main__":
    sys.exit(main())
