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

An OBJECT LIST is several registrations. Turtle permits
`solid:forClass a:X, b:Y ;` and both classes are registered by it. The pattern
used to require a single non-space token before the terminator, which did not
truncate such a line so much as fail to match it at all -- every class in it
was dropped, and the same silent omission again.

Exit status: 0 if every registered class carries the marker, 1 on any finding,
and 1 if no registration was found at all -- a check with no material to inspect
has proven nothing.

Usage:  python3 scripts/check-record-class-registry.py [spec-root]

Requires: rdflib (see scripts/requirements.txt)
"""

import os
import re
import sys

# The ontology corpus -- the glob, the .shapes.ttl exclusion, the marker -- is
# defined once, in cascade_ontology, because check-context-coverage.py compares
# against the same corpus and a second copy of that definition is a second
# thing that can drift. See that module's docstring.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from cascade_ontology import (  # noqa: E402  (needs the path insert above)
    CASCADE_NS_PREFIX,
    ONTOLOGY_GLOB,
    RECORD_CLASS_MARKER,
    load_ontology,
    spec_root,
)
from rdflib import RDF, URIRef  # noqa: E402  (guarded by the import above)

POD_STRUCTURE = "pod-structure.md"

# Everything between solid:forClass and the `;` or `.` that closes the
# predicate-object pair -- which may be an OBJECT LIST, since Turtle permits
# `solid:forClass a:X, b:Y ;` and every object in it registers a class.
#
# DELIBERATELY WIDE IN BOTH DIRECTIONS. This required a single non-space token
# before the terminator, which did not merely truncate an object list: the
# pattern failed to match such a line AT ALL, so every class in it was dropped
# and no pod path in it was ever compared to a marker. Reading the whole region
# and then JUDGING each token is the point -- a narrower pattern makes an
# unrecognised registration invisible instead of reporting it, which is the
# silent omission this check exists to catch (see registered_classes).
REGISTRATION = re.compile(r"solid:forClass\s+([^;.]+)[;.]")
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

    ONE PREDICATE, POSSIBLY SEVERAL OBJECTS. Turtle's comma separates objects
    of a shared predicate, so `solid:forClass a:X, b:Y ;` registers both and
    each object is judged on its own marker.

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
    for objects in REGISTRATION.findall(text):
        # One predicate-object pair, so possibly several objects: Turtle's
        # comma separates them and each is its own registration.
        for token in (part.strip() for part in objects.split(",")):
            if not token:
                continue
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


def main():
    root = spec_root(sys.argv[1:])

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
