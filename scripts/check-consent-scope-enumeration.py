#!/usr/bin/env python3
"""check-consent-scope-enumeration.py — cascade:consentScope's value set is OPEN,
and only the value set is advisory.

Run from the spec repo root:
    python3 scripts/check-consent-scope-enumeration.py
    python3 scripts/check-consent-scope-enumeration.py path/to/other/root

WHY THIS EXISTS
---------------
D-CONSENT-1 (decisions/2026-09-01-consent-architecture.md) ratified the consent
scope value set as `social-history`, `substance-use`, `mental-health`, and
ratified it as OPEN:

    The enumeration stays OPEN (sh:in at sh:Warning at most, never
    sh:Violation). Part 2 is US-specific and sensitivity categories grow;
    reproductive health and genomics are foreseeable members. A closed list
    missing a member rejects conformant data.

core.shapes.ttl v1.8 shipped the opposite: a one-member sh:in at sh:Violation,
so a record tagged substance-use or mental-health — data the decision calls
conformant — is REJECTED. That is the defect this check exists to prevent
returning.

WHAT IT ASSERTS, AND WHY EACH ONE IS SEPARATE
---------------------------------------------
CS1  Every ratified scope is a declared cascade:ConsentScope named individual.
     An sh:in member with no declaration is a dangling IRI: sh:in compares IRIs
     and would happily enumerate a typo forever.

CS2  The sh:in on cascade:consentScope enumerates all three ratified scopes.
     "At least", not "exactly": the list is open and expected to grow
     (reproductive health, genomics). A check that pinned the membership shut
     would re-close by the back door what it exists to keep open.

CS3  Every property shape carrying that sh:in is sh:Warning. This is the
     openness itself. A closed enumeration and a Violation-severity one are the
     same thing to a producer: both reject a member the list has not caught up
     to yet.

CS4  SEVERITY IS TWO CONSTRAINTS, NOT ONE. The ratification demotes the VALUE
     SET. It says nothing about sh:nodeKind / sh:minCount / sh:maxCount, and
     demoting those too would silently turn "two consent scopes on one record"
     and "a literal instead of an IRI" into warnings, which nothing asked for.
     So the structural constraints must live on a property shape that carries
     no sh:in and stays sh:Violation. The block splits; it does not soften.

CS5  Nothing reaches cascade:ConsentScopeShape by sh:node or
     sh:qualifiedValueShape. This is rule S5 (validation/index.md) as a
     PRECONDITION rather than a prohibition: SHACL conformance is an empty
     result set and does not read severity, so a Warning on a shape something
     reaches by sh:node is re-reported to the referring class as a Violation.
     CS3's demotion is real only while CS5 holds. clinical v1.16 shipped a
     Warning that was delivered as a rejection on six document classes;
     check-nested-severity.py is the general gate, and this is the local
     statement that the gate has nothing to find here.

WHAT THIS CHECK IS NOT: it is not a SHACL run. spec deliberately does not depend
on pyshacl (scripts/requirements.txt says so), so this reasons over the shapes
graph, like check-shape-targets.py and check-nested-severity.py. The behavioural
verification — that graph 2 conforms and graph 3 reports Warning-and-only-Warning
— lives in the conformance repository and cannot be run here.
"""

import glob
import os
import sys

from rdflib import Graph, Namespace, URIRef
from rdflib.namespace import OWL, RDF

SH = Namespace("http://www.w3.org/ns/shacl#")
CASCADE = Namespace("https://ns.cascadeprotocol.org/core/v1#")

CONSENT_SCOPE_SHAPE = CASCADE.ConsentScopeShape
CONSENT_SCOPE = CASCADE.consentScope
CONSENT_SCOPE_CLASS = CASCADE.ConsentScope

# The list authored in sdk-typescript 9ea7c78 and ratified by D-CONSENT-1:
# social-history, substance-use, mental-health.
RATIFIED_SCOPES = [
    CASCADE.SocialHistoryConsent,
    CASCADE.SubstanceUseConsent,
    CASCADE.MentalHealthConsent,
]

STRUCTURAL_CONSTRAINTS = [SH.nodeKind, SH.minCount, SH.maxCount]


def qname(term):
    s = str(term)
    if s.startswith(str(CASCADE)):
        return "cascade:" + s[len(str(CASCADE)):]
    if s.startswith(str(SH)):
        return "sh:" + s[len(str(SH)):]
    return s


def describe(graph, shape):
    """Name a property shape usefully. Most are blank nodes hanging off a node
    shape by sh:property, and a bare b-node label tells a reader nothing."""
    if isinstance(shape, URIRef):
        return qname(shape)
    parents = sorted(set(graph.subjects(SH.property, shape)), key=str)
    if parents:
        return "the sh:property block on " + ", ".join(qname(p) for p in parents)
    return f"property shape {shape}"


def severity_of(graph, shape):
    """SHACL's default severity is sh:Violation when none is declared."""
    declared = graph.value(shape, SH.severity)
    return declared if declared is not None else SH.Violation


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ".."
    )
    root = os.path.abspath(root)

    core_ttl = os.path.join(root, "ontologies", "core", "v1", "core.ttl")
    if not os.path.isfile(core_ttl):
        print(f"ERROR: no core ontology at {core_ttl}", file=sys.stderr)
        return 2

    shape_files = sorted(
        glob.glob(os.path.join(root, "ontologies", "**", "*.shapes.ttl"), recursive=True)
    )
    if not shape_files:
        print(f"ERROR: no *.shapes.ttl under {root}", file=sys.stderr)
        return 2

    onto = Graph()
    shapes = Graph()
    try:
        onto.parse(core_ttl, format="turtle")
        for path in shape_files:
            shapes.parse(path, format="turtle")
    except Exception as exc:  # noqa: BLE001 - a parse failure is a hard error
        print(f"ERROR: parse failed: {exc}", file=sys.stderr)
        return 2

    print("Consent scope open-enumeration check")
    print(f"  root:          {root}")
    print(f"  shapes parsed: {len(shape_files)}")
    print("")

    failures = []

    def record(tag, ok, summary, detail=""):
        if ok:
            print(f"  PASS  [{tag}] {summary}")
        else:
            print(f"  FAIL  [{tag}] {summary}")
            if detail:
                for line in detail.splitlines():
                    print(f"              {line}")
            failures.append(tag)

    # ---------------------------------------------------------------- CS1
    undeclared = []
    for scope in RATIFIED_SCOPES:
        types = set(onto.objects(scope, RDF.type))
        if OWL.NamedIndividual not in types or CONSENT_SCOPE_CLASS not in types:
            undeclared.append(
                f"{qname(scope)}: types = "
                + (", ".join(sorted(qname(t) for t in types)) if types else "(none)")
            )
    record(
        "CS1",
        not undeclared,
        "every ratified scope is a declared cascade:ConsentScope named individual",
        "expected: a owl:NamedIndividual, cascade:ConsentScope in core.ttl\n"
        + "\n".join(undeclared),
    )

    # Property shapes constraining cascade:consentScope, wherever they live.
    scope_shapes = sorted(
        set(shapes.subjects(SH.path, CONSENT_SCOPE)), key=str
    )
    if not scope_shapes:
        record(
            "CS0",
            False,
            "some property shape constrains cascade:consentScope",
            "no subject in any *.shapes.ttl carries sh:path cascade:consentScope",
        )
        print("")
        print("RESULT: FAIL - nothing constrains cascade:consentScope at all.")
        return 1

    in_shapes = [s for s in scope_shapes if shapes.value(s, SH["in"]) is not None]
    structural_shapes = [
        s
        for s in scope_shapes
        if any(shapes.value(s, c) is not None for c in STRUCTURAL_CONSTRAINTS)
    ]

    # ---------------------------------------------------------------- CS2
    enumerated = set()
    for s in in_shapes:
        enumerated.update(shapes.items(shapes.value(s, SH["in"])))
    missing = [scope for scope in RATIFIED_SCOPES if scope not in enumerated]
    record(
        "CS2",
        bool(in_shapes) and not missing,
        "sh:in enumerates all three ratified scopes",
        "enumerated: "
        + (", ".join(sorted(qname(m) for m in enumerated)) if enumerated else "(no sh:in found)")
        + "\nmissing:    "
        + ", ".join(qname(m) for m in missing),
    )

    # ---------------------------------------------------------------- CS3
    hard_value_sets = [
        s for s in in_shapes if severity_of(shapes, s) != SH.Warning
    ]
    record(
        "CS3",
        bool(in_shapes) and not hard_value_sets,
        "the sh:in value set is sh:Warning, never sh:Violation",
        "\n".join(
            f"{describe(shapes, s)}: sh:severity {qname(severity_of(shapes, s))}"
            for s in hard_value_sets
        ),
    )

    # ---------------------------------------------------------------- CS4
    cs4_problems = []
    shared = [s for s in structural_shapes if s in in_shapes]
    for s in shared:
        cs4_problems.append(
            f"{describe(shapes, s)} carries sh:in AND "
            + ", ".join(
                qname(c) for c in STRUCTURAL_CONSTRAINTS if shapes.value(s, c) is not None
            )
            + " in one property block; the value set cannot be demoted without demoting them too"
        )
    strict_only = [s for s in structural_shapes if s not in in_shapes]
    for s in strict_only:
        if severity_of(shapes, s) != SH.Violation:
            cs4_problems.append(
                f"{describe(shapes, s)}: structural constraints at sh:severity "
                f"{qname(severity_of(shapes, s))}, expected sh:Violation"
            )
    present = {
        c
        for s in structural_shapes
        for c in STRUCTURAL_CONSTRAINTS
        if shapes.value(s, c) is not None
    }
    for c in STRUCTURAL_CONSTRAINTS:
        if c not in present:
            cs4_problems.append(f"no property shape constrains {qname(c)} on cascade:consentScope")
    record(
        "CS4",
        bool(strict_only) and not cs4_problems,
        "sh:nodeKind / sh:minCount / sh:maxCount are a separate sh:Violation block",
        "\n".join(cs4_problems)
        or "no property shape carries the structural constraints without sh:in",
    )

    # ---------------------------------------------------------------- CS5
    nested_refs = []
    for pred in (SH.node, SH.qualifiedValueShape):
        for subj in shapes.subjects(pred, CONSENT_SCOPE_SHAPE):
            nested_refs.append(f"{describe(shapes, subj)} {qname(pred)} cascade:ConsentScopeShape")
    record(
        "CS5",
        not nested_refs,
        "nothing reaches cascade:ConsentScopeShape by sh:node or sh:qualifiedValueShape",
        "a Warning on a shape reached this way is delivered as a Violation (rule S5)\n"
        + "\n".join(nested_refs),
    )

    print("")
    if failures:
        print(f"RESULT: FAIL - {len(failures)} assertion(s) failed: {', '.join(failures)}")
        return 1
    print(f"RESULT: PASS - {len(scope_shapes)} property shape(s) on cascade:consentScope.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
