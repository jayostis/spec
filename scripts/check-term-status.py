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
from rdflib.namespace import OWL, RDF, RDFS

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

CASCADE_NS_PREFIX = "https://ns.cascadeprotocol.org/"


def is_cascade(term):
    return str(term).startswith(CASCADE_NS_PREFIX)


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


def check_successors(paths):
    """A deprecated class must name its replacement in a triple.

    rdfs:seeAlso on a deprecated class is what lets a reader map an old spelling
    onto the live one. Four of the five deprecated classes carried it correctly
    and clinical:CoverageRecord did not: its only rdfs:seeAlso pointed at
    fhir:Coverage, a documentation link, while the supersession by
    coverage:InsurancePlan was stated in prose and in no triple. That is the one
    deprecation whose replacement lives in a different vocabulary -- the case
    where a consumer is least able to guess -- and it is how sdk-typescript's
    InsurancePlan spent five releases pointing at the dead class.

    A DOCUMENTATION LINK IS NOT A SUCCESSOR. The rule needs at least one
    rdfs:seeAlso resolving to a live Cascade TERM, so fhir:Coverage does not
    satisfy it and does not have to be removed to satisfy it.

    A SUCCESSOR NEED NOT BE A CLASS. evidence:VerdictValue is the worked example
    for that: a flat enumeration replaced by five facet PROPERTIES
    (evidence:direction / basis / strength / settled / reason), so a
    class-only rule would have demanded a replacement that does not exist and
    been relaxed or switched off. What matters is that the vocabulary says what
    to use instead in a triple, not that the answer has the same arity.

    SCOPE IS EVERY VOCABULARY, NOT JUST THE DRAFTS. The vs:term_status rules
    above run over v1-draft only, because stable vocabularies do not annotate
    maturity per term and checking them would report every stable term as
    missing. Deprecation is the opposite: all five deprecated classes are in
    stable clinical:, so a draft-only scope would have examined none of them.
    """
    graph = Graph()
    for path in paths:
        graph.parse(path, format="turtle")

    # Every Cascade term, so a successor may be a property as well as a class.
    terms = {
        s for s, _, o in graph.triples((None, RDF.type, None))
        if o in TERM_TYPES and isinstance(s, URIRef) and is_cascade(s)
    }
    is_dead = {
        t for t in terms
        if any(bool(o) for o in graph.objects(t, OWL.deprecated))
    }
    # Only CLASSES are required to name a successor. A deprecated property is
    # usually dropped rather than replaced one-for-one, and demanding a triple
    # for each would be a rule nobody could satisfy honestly.
    deprecated = {c for c in is_dead if (c, RDF.type, OWL.Class) in graph}

    findings = []
    for cls in sorted(deprecated):
        successors = [
            o for o in graph.objects(cls, RDFS.seeAlso)
            if isinstance(o, URIRef) and is_cascade(o) and o not in is_dead
        ]
        if not successors:
            seen = [str(o) for o in graph.objects(cls, RDFS.seeAlso)]
            findings.append((cls, seen))

    print(f"{'deprecation successors':22s} {len(deprecated):4d} deprecated "
          f"class(es), {len(deprecated) - len(findings):4d} naming a successor, "
          f"{len(findings):3d} not")
    for cls, seen in findings:
        print(f"      NO SUCCESSOR TRIPLE on {local(cls)} "
              f"(rdfs:seeAlso: {seen or 'none'})", file=sys.stderr)
        print(f"      A deprecated class must name its replacement with an "
              f"rdfs:seeAlso resolving to a live Cascade class. A link to "
              f"external documentation does not say what to use instead.",
              file=sys.stderr)
    return len(findings)


def main():
    paths = sys.argv[1:]
    explicit = bool(paths)
    if not paths:
        paths = sorted(p for p in glob.glob("ontologies/*/v1-draft/*.ttl")
                       if not p.endswith(".shapes.ttl"))
    if not paths:
        print("Error: no draft ontologies found. Run from the spec repo root.",
              file=sys.stderr)
        return 1

    problems = sum(check(p) for p in paths)

    # The successor rule reads every vocabulary, stable included -- see
    # check_successors. When files were named explicitly, honour that scope
    # rather than silently widening past what the caller asked about.
    successor_paths = paths if explicit else sorted(
        p for p in glob.glob("ontologies/*/v1*/*.ttl")
        if not p.endswith(".shapes.ttl")
    )
    if not successor_paths:
        print("Error: no ontologies found for the successor check.",
              file=sys.stderr)
        return 1
    problems += check_successors(successor_paths)

    print()
    if problems:
        print(f"FAILED: {problems} problem(s).", file=sys.stderr)
        return 1
    print("All draft terms declare a valid vs:term_status, and every deprecated "
          "class names a live successor.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
