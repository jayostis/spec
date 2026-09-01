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

     SCOPED TO cascade:ConsentScopeShape'S OWN sh:property BLOCKS, deliberately.
     CS4's subject is that shape's block split, not a claim on every shape in
     the corpus that mentions the predicate. core.shapes.ttl documents the next
     ratchet step as sh:minCount 1 at sh:Warning on
     clinical:SocialHistoryRecordShape -- a presence constraint on a record
     class, which is not a softening of the value shape and is nobody's defect.
     A corpus-wide CS4 would fail on this repository's own documented next move,
     and the cheapest-looking fix for that red build is to weaken CS4. Other
     shapes' severities are the general gate's business.

CS5  Nothing reaches cascade:ConsentScopeShape by any parameter that collapses
     its result set to a boolean. This is rule S5 (validation/index.md) as a
     PRECONDITION rather than a prohibition: SHACL conformance is an empty
     result set and does not read severity, so a Warning on a shape something
     reaches that way is re-reported to the referring class as a Violation.
     CS3's demotion is real only while CS5 holds. clinical v1.16 shipped a
     Warning that was delivered as a rejection on six document classes;
     check-nested-severity.py is the general gate, and this is the local
     statement that the gate has nothing to find here.

     sh:node and sh:qualifiedValueShape are not the whole set. sh:not takes a
     shape directly, and sh:or / sh:and / sh:xone take a LIST of shapes; all
     four evaluate the referenced shape for conformance and re-report at the
     REFERRING shape's severity, so any of them would close the enumeration in
     practice while a narrower CS5 printed PASS. check-nested-severity.py does
     not backstop this either: its NESTED_SHAPE_PARAMS is the same pair, and it
     walks the list parameters only for reachability FROM a shape already
     referenced by that pair.

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

# CS5's predicate set. Every parameter whose value is a SHAPE the node must
# CONFORM TO collapses that shape's result set to a boolean and re-reports it at
# the referring shape's severity -- which is what would deliver the sh:in
# Warning as a rejection. sh:node, sh:qualifiedValueShape and sh:not name a
# shape directly; sh:or, sh:and and sh:xone name an RDF list of them.
NESTING_PARAMS = (SH.node, SH.qualifiedValueShape, SH["not"])
NESTING_LIST_PARAMS = (SH["or"], SH["and"], SH.xone)


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

    # CS4 is about ONE shape's block split, so it reads only the property shapes
    # cascade:ConsentScopeShape itself reaches by sh:property (plus the shape
    # itself, for a corpus that ever publishes it as a bare sh:PropertyShape).
    # Scoping is load-bearing: see CS4 in the module docstring.
    own_shapes = sorted(
        {
            s
            for s in shapes.objects(CONSENT_SCOPE_SHAPE, SH.property)
            if s in set(scope_shapes)
        }
        | ({CONSENT_SCOPE_SHAPE} if CONSENT_SCOPE_SHAPE in set(scope_shapes) else set()),
        key=str,
    )
    structural_shapes = [
        s
        for s in own_shapes
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
            cs4_problems.append(
                f"no sh:property block on cascade:ConsentScopeShape constrains {qname(c)}"
            )
    record(
        "CS4",
        bool(strict_only) and not cs4_problems,
        "sh:nodeKind / sh:minCount / sh:maxCount are a separate sh:Violation block "
        "on cascade:ConsentScopeShape",
        "\n".join(cs4_problems)
        or "no sh:property block on cascade:ConsentScopeShape carries the "
        "structural constraints without sh:in",
    )

    # ---------------------------------------------------------------- CS5
    nested_refs = []
    for pred in NESTING_PARAMS:
        for subj in shapes.subjects(pred, CONSENT_SCOPE_SHAPE):
            nested_refs.append(f"{describe(shapes, subj)} {qname(pred)} cascade:ConsentScopeShape")
    for pred in NESTING_LIST_PARAMS:
        for subj, head in shapes.subject_objects(pred):
            try:
                members = list(shapes.items(head))
            except Exception:  # noqa: BLE001 - a malformed list is not CS5's finding
                continue
            if CONSENT_SCOPE_SHAPE in members:
                nested_refs.append(
                    f"{describe(shapes, subj)} {qname(pred)} ( ... cascade:ConsentScopeShape ... )"
                )
    record(
        "CS5",
        not nested_refs,
        "nothing reaches cascade:ConsentScopeShape by sh:node, sh:qualifiedValueShape, "
        "sh:not, sh:or, sh:and or sh:xone",
        "a Warning on a shape reached this way is delivered as a Violation (rule S5)\n"
        + "\n".join(sorted(set(nested_refs))),
    )

    print("")
    if failures:
        print(f"RESULT: FAIL - {len(failures)} assertion(s) failed: {', '.join(failures)}")
        return 1
    print(f"RESULT: PASS - {len(scope_shapes)} property shape(s) on cascade:consentScope.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
