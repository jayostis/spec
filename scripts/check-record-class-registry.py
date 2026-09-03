#!/usr/bin/env python3
"""check-record-class-registry.py: a class a Pod stores must say that it does.

THE RULE

pod-structure.md registers classes in Solid type-index form:

    <#lab-results>
        a solid:TypeRegistration ;
        solid:forClass health:LabResultRecord ;
        solid:instanceContainer </clinical/lab-results.ttl> .

A type registration says instances of that class live at that path -- which is
exactly the claim `a cascade:RecordClass` makes in the ontology. So every class
named by a solid:forClass here MUST carry the marker. If it does not, the
specification says a Pod stores the class in one document and says nothing about
it in another, and scripts/check-class-coverage.py -- which keys on the marker --
never asks whether a shape judges those records.

WHY THIS EXISTS AS A SEPARATE CHECK

The marker is an explicit designation (jayostis/spec#34 ruled out deriving it
from rdfs:subClassOf prov:Entity, which is PROV-O alignment). An explicit list
is only as good as its curation, and the failure mode of a hand-maintained list
is silent omission: a class gets added to the vocabulary and to the pod layout
and nobody marks it, and nothing notices, because a missing entry looks exactly
like a class that was considered and correctly excluded.

pod-structure.md is the one other place in this repository that enumerates
stored record types, it is maintained by different edits for a different reason,
and it was audited at v1.1 against the reference patient pod ("Fourteen class
names were corrected"). Two independently maintained sources of the same fact,
compared, catch the omission that neither catches alone.

DIRECTION, DELIBERATELY

Registered => marked. NOT the converse. The type index covers pod-level
aggregate files, which is a strict subset of the record classes: nested and
per-record classes (clinical:EncounterParticipant, cascade:ConflictDetail) are
stored inside another document rather than at their own path and are correctly
absent from it. Requiring marked => registered would demand a pod path for every
one of them.

WHAT IS NOT CHECKED

That a registered class exists at all is check-class-coverage.py's business via
the ontology load, and a class named here that no ontology declares is reported
as unmarked -- which is the right answer for a different reason, and the message
says so.

Exit status: 0 if every registered class carries the marker, 1 on any finding,
and 1 if no registration was found at all -- a check with no material to inspect
has proven nothing.

Usage:  python3 scripts/check-record-class-registry.py [spec-root]

Requires: rdflib (see scripts/requirements.txt)
"""

import glob
import os
import re
import sys

try:
    from rdflib import Graph, RDF, URIRef
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
POD_STRUCTURE = "pod-structure.md"

# Prefix -> namespace segment. `cascade:` is the core vocabulary, whose
# directory is `core/`; the rest are named after their directory.
PREFIX_SEGMENT = {
    "cascade": "core/v1#",
    "health": "health/v1#",
    "clinical": "clinical/v1#",
    "coverage": "coverage/v1#",
    "checkup": "checkup/v1#",
    "pots": "pots/v1#",
}

# `solid:forClass {vocabulary}:{ClassName}` is the documented TEMPLATE in the
# registration-format section, not a registration. A brace in either position
# means the line is showing the shape rather than making a claim.
REGISTRATION = re.compile(r"solid:forClass\s+([a-z]+):([A-Za-z][A-Za-z0-9]*)\s*[;.]")


def registered_classes(root):
    """(prefixed name, IRI) for every solid:forClass registration, deduplicated
    and in first-seen order so the report reads in document order."""
    path = os.path.join(root, POD_STRUCTURE)
    if not os.path.exists(path):
        sys.stderr.write("ERROR: %s not found under %s\n" % (POD_STRUCTURE, root))
        sys.exit(2)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    seen, out = set(), []
    for prefix, local in REGISTRATION.findall(text):
        if prefix not in PREFIX_SEGMENT:
            continue
        name = "%s:%s" % (prefix, local)
        if name in seen:
            continue
        seen.add(name)
        out.append((name, URIRef(CASCADE_NS_PREFIX + PREFIX_SEGMENT[prefix] + local)))
    return out


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


def main():
    args = [a for a in sys.argv[1:]]
    root = args[0] if args else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ".."
    )
    root = os.path.abspath(root)

    ontology, onto_files = load_ontology(root)
    registrations = registered_classes(root)
    marked = set(ontology.subjects(RDF.type, RECORD_CLASS_MARKER))
    declared = set(ontology.subjects(RDF.type, URIRef(
        "http://www.w3.org/2002/07/owl#Class")))

    print("Record-class registry agreement check")
    print("  root:              %s" % root)
    print("  ontologies parsed: %d" % len(onto_files))
    print("  registrations:     %d  (solid:forClass in %s)"
          % (len(registrations), POD_STRUCTURE))
    print("  marked classes:    %d  (a cascade:RecordClass)" % len(marked))
    print()

    if not registrations:
        print("EMPTY: no solid:forClass registration found in %s." % POD_STRUCTURE)
        print("RESULT: FAIL")
        return 1

    unmarked = [(n, u) for n, u in registrations if u not in marked]

    if unmarked:
        print("FAIL  %d registered class(es) carry no cascade:RecordClass marker:"
              % len(unmarked))
        for name, uri in unmarked:
            note = "" if uri in declared else "   (and no ontology declares it)"
            print("        %s%s" % (name, note))
        print()
        print("      %s registers each of these with solid:forClass, which says a" % POD_STRUCTURE)
        print("      Pod stores instances of the class at a path. The ontology does")
        print("      not say so, and check-class-coverage.py keys on the marker, so")
        print("      nothing asks whether a shape judges those records.")
        print()
        print("      Add `a cascade:RecordClass` to the class -- or, if a Pod does")
        print("      not in fact store it, remove the registration. Two sources")
        print("      disagreeing is the finding; which one is wrong is a judgement.")
        print()
        print("RESULT: FAIL")
        return 1

    print("RESULT: PASS, %d registered class(es) all carry the marker."
          % len(registrations))
    return 0


if __name__ == "__main__":
    sys.exit(main())
