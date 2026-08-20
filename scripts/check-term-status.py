#!/usr/bin/env python3
"""check-term-status.py — every draft term must declare a valid vs:term_status.

Run from the spec repo root:
    python3 scripts/check-term-status.py                 # all draft vocabularies
    python3 scripts/check-term-status.py path/to/x.ttl   # specific files

WHY THIS EXISTS
---------------
Cascade used to state maturity once per VOCABULARY, in prose. The W3C SemWeb
Vocabulary Status ontology (http://www.w3.org/2003/06/sw-vocab-status/ns#,
originating in FOAF) states it per TERM, and its own description says why:
recording status at the term level rather than the vocabulary level makes
fine-grained improvement easier. That is precisely the guarantee a /v1#
namespace already makes, so a vocabulary can promote individual terms in place
without minting a new namespace. Adopted 2026-08-20 across the five draft
vocabularies.

It is CHECKED rather than trusted because the pass that added these annotations
silently skipped 96 of 411 terms -- every term that happened to be preceded by a
section comment -- and reported success. A tool's own count of what it did is
not evidence. This reads the parsed graph instead.

Values are the four the ontology defines: unstable, testing, stable, archaic.
A term marked owl:deprecated must be archaic; that is the one pairing the two
vocabularies both have an opinion about, and disagreeing would leave a consumer
with two contradictory machine-readable answers.
"""

import glob
import sys

from rdflib import Graph, Namespace, URIRef
from rdflib.namespace import OWL, RDF

VS = Namespace("http://www.w3.org/2003/06/sw-vocab-status/ns#")
TERM_STATUS = VS.term_status

TERM_TYPES = {
    OWL.Class,
    OWL.ObjectProperty,
    OWL.DatatypeProperty,
    OWL.AnnotationProperty,
    OWL.NamedIndividual,
    URIRef("http://www.w3.org/1999/02/22-rdf-syntax-ns#Property"),
}

VALID = {"unstable", "testing", "stable", "archaic"}


def local(term):
    s = str(term)
    return s.rsplit("#", 1)[-1] if "#" in s else s.rsplit("/", 1)[-1]


def check(path):
    g = Graph()
    g.parse(path, format="turtle")

    terms = {s for s, _, o in g.triples((None, RDF.type, None))
             if o in TERM_TYPES and isinstance(s, URIRef)}
    # The ontology header declares itself owl:Ontology, not a term type, so it
    # is already excluded and must stay that way: its maturity is versionInfo.

    missing, bad, deprecated_not_archaic = [], [], []
    for term in sorted(terms):
        values = [str(o) for o in g.objects(term, TERM_STATUS)]
        if not values:
            missing.append(term)
            continue
        for v in values:
            if v not in VALID:
                bad.append((term, v))
        if (term, OWL.deprecated, None) in g:
            if any(bool(o) for o in g.objects(term, OWL.deprecated)):
                if "archaic" not in values:
                    deprecated_not_archaic.append((term, values))

    name = path.rsplit("/", 1)[-1]
    print(f"{name:22s} {len(terms):4d} terms, "
          f"{len(terms) - len(missing):4d} with status, {len(missing):3d} missing")
    for t in missing[:25]:
        print(f"      MISSING vs:term_status: {local(t)}", file=sys.stderr)
    for t, v in bad:
        print(f"      INVALID value {v!r} on {local(t)} "
              f"(expected one of {sorted(VALID)})", file=sys.stderr)
    for t, v in deprecated_not_archaic:
        print(f"      owl:deprecated but term_status {v} on {local(t)} "
              f"(expected archaic)", file=sys.stderr)
    return len(missing) + len(bad) + len(deprecated_not_archaic)


def main():
    paths = sys.argv[1:]
    if not paths:
        paths = sorted(p for p in glob.glob("ontologies/*/v1-draft/*.ttl")
                       if not p.endswith(".shapes.ttl"))
    if not paths:
        print("Error: no draft ontologies found. Run from the spec repo root.",
              file=sys.stderr)
        return 1

    problems = sum(check(p) for p in paths)
    print()
    if problems:
        print(f"FAILED: {problems} problem(s).", file=sys.stderr)
        return 1
    print("All draft terms declare a valid vs:term_status.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
