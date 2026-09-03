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

NOTHING IS SKIPPED

A registration this check cannot resolve to a class is reported and fails. It
used to be dropped, because prefixes came from a hardcoded table of the six
stable vocabularies: a draft class, or a typo like `helth:LabResultRecord`,
registered a pod path and was compared to nothing, which is precisely the
silent omission above. Prefixes now come from the ontologies' own @prefix
declarations, and whatever still does not resolve is a finding. The single
exception is the documented TEMPLATE `solid:forClass {vocabulary}:{ClassName}`,
which names no class by design.

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

# The whole token after solid:forClass, whatever shape it is. Reading it and
# then JUDGING it is the point: a narrower pattern makes an unrecognised
# registration invisible instead of reporting it (see registered_classes).
REGISTRATION = re.compile(r"solid:forClass\s+(\S+)\s*[;.]")
QNAME = re.compile(r"^([A-Za-z][A-Za-z0-9]*):([A-Za-z][A-Za-z0-9_-]*)$")


def cascade_namespaces(graph):
    """prefix -> namespace IRI, as the ontology files themselves declare it.

    DERIVED, NOT TABULATED. This was a six-entry table of the stable
    vocabularies, which meant a registration for a draft class resolved to
    nothing and was skipped -- silently, by the check whose stated purpose is to
    catch silent omission. Reading the @prefix declarations out of the parsed
    ontologies covers every vocabulary that exists, drafts included, and keeps
    covering the next one without an edit here.
    """
    out = {}
    for prefix, namespace in graph.namespaces():
        if str(namespace).startswith(CASCADE_NS_PREFIX):
            out[str(prefix)] = str(namespace)
    return out


def registered_classes(root, namespaces):
    """(registrations, unresolved) for every solid:forClass in pod-structure.md.

    Registrations are (prefixed name, IRI), deduplicated and in first-seen order
    so the report reads in document order. `unresolved` holds the tokens that
    name no resolvable class -- an unknown prefix, a typo like `helth:`, a
    spelling that is not a qname at all.

    AN UNRESOLVED REGISTRATION IS A FINDING, NOT A NON-REGISTRATION. Skipping it
    is how `helth:LabResultRecord` or a draft class registers a pod path and is
    compared to nothing, which is the exact failure mode this check exists to
    catch. The one thing that is genuinely not a registration is the documented
    TEMPLATE, `solid:forClass {vocabulary}:{ClassName}`: a brace means the line
    is showing the shape rather than making a claim.
    """
    path = os.path.join(root, POD_STRUCTURE)
    if not os.path.exists(path):
        sys.stderr.write("ERROR: %s not found under %s\n" % (POD_STRUCTURE, root))
        sys.exit(2)
    with open(path, encoding="utf-8") as handle:
        text = handle.read()

    seen, out, unresolved = set(), [], []
    for token in REGISTRATION.findall(text):
        if "{" in token or "}" in token:
            continue
        if token in seen:
            continue
        seen.add(token)
        match = QNAME.match(token)
        if match and match.group(1) in namespaces:
            out.append((token, URIRef(namespaces[match.group(1)] + match.group(2))))
        else:
            unresolved.append(token)
    return out, unresolved


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
    namespaces = cascade_namespaces(ontology)
    registrations, unresolved = registered_classes(root, namespaces)
    marked = set(ontology.subjects(RDF.type, RECORD_CLASS_MARKER))
    declared = set(ontology.subjects(RDF.type, URIRef(
        "http://www.w3.org/2002/07/owl#Class")))

    print("Record-class registry agreement check")
    print("  root:              %s" % root)
    print("  ontologies parsed: %d" % len(onto_files))
    print("  vocabularies:      %d  (Cascade @prefix declarations found)"
          % len(namespaces))
    print("  registrations:     %d  (solid:forClass in %s)"
          % (len(registrations), POD_STRUCTURE))
    print("  unresolved:        %d  (solid:forClass naming no resolvable class)"
          % len(unresolved))
    print("  marked classes:    %d  (a cascade:RecordClass)" % len(marked))
    print()

    if not registrations and not unresolved:
        print("EMPTY: no solid:forClass registration found in %s." % POD_STRUCTURE)
        print("RESULT: FAIL")
        return 1

    findings = 0

    if unresolved:
        findings += len(unresolved)
        print("FAIL  %d registration(s) name no class this check can resolve:"
              % len(unresolved))
        for token in unresolved:
            print("        solid:forClass %s" % token)
        print()
        print("      The prefix is declared by no ontology under %s, or the token"
              % ONTOLOGY_GLOB)
        print("      is not a qname at all. Either way the registration claims a Pod")
        print("      stores instances of something, and this check cannot say what.")
        print()
        print("      Skipping it would make this check perform the silent omission")
        print("      it exists to catch: `helth:LabResultRecord` registers a path,")
        print("      matches no class, and gets compared to nothing. Correct the")
        print("      prefix, or publish the vocabulary under ontologies/ so its")
        print("      namespace declaration is loaded.")
        print()

    unmarked = [(n, u) for n, u in registrations if u not in marked]

    if unmarked:
        findings += len(unmarked)
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

    if findings:
        print("RESULT: FAIL")
        return 1

    print("RESULT: PASS, %d registered class(es) all carry the marker."
          % len(registrations))
    return 0


if __name__ == "__main__":
    sys.exit(main())
