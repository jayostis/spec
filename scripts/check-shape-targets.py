#!/usr/bin/env python3
"""check-shape-targets.py: enforce the entailment-independence rule on this
repository's own SHACL shapes.

The rule is stated normatively in validation/index.md. In short: SHACL resolves
class membership over the DATA graph, so a validator that performs no RDFS
entailment sees only the rdf:type triples a record actually carries. A shape
that reaches a class only through an rdfs:subClassOf axiom in an ontology file
therefore fires in an entailing validator and stays silent in a strictly
conforming one. Two implementations then disagree about whether the same file
is valid.

These shapes must behave identically in both. This script proves it by
construction, over three assertions:

  T  TARGET CLOSURE
     If a class has a proper superclass that some shape targets, the class
     itself must be targeted by some shape. Otherwise an entailing validator
     checks its instances and a non-entailing one checks nothing.

  I  CONSTRAINT-SET EQUIVALENCE
     A class whose superclass is targeted must reach that superclass's
     constraints explicitly: either the same shape targets both, or the
     subclass's shape names the superclass's shape with sh:node. Otherwise the
     two engines apply different constraint sets to the same node.

  C  VALUE-CLASS CLOSURE
     sh:class is resolved the same way as sh:targetClass. The set of classes
     accepted at one constraint site must be closed under rdfs:subClassOf, so
     enumerate the acceptable subclasses (sh:or) rather than relying on the
     superclass name to cover them.

Exit status: 0 if every assertion holds, 1 if any fails or if the run examined
nothing (a check that found no material to inspect has proven nothing and is
reported as a failure, not a pass).

Usage:  python3 scripts/check-shape-targets.py [spec-root]
Requires: rdflib (see scripts/requirements.txt)
"""

import glob
import os
import sys

try:
    from rdflib import Graph, RDF, RDFS, OWL, URIRef, Namespace
except ImportError:  # pragma: no cover - environment guard
    sys.stderr.write(
        "ERROR: rdflib is not installed. This check parses Turtle and cannot\n"
        "       degrade to a text scan without becoming unsound.\n"
        "       Install it with:  python3 -m pip install -r scripts/requirements.txt\n"
    )
    sys.exit(2)

SH = Namespace("http://www.w3.org/ns/shacl#")
CASCADE_NS_PREFIX = "https://ns.cascadeprotocol.org/"

ONTOLOGY_GLOB = "ontologies/*/v1*/*.ttl"


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load(root):
    """Parse every ontology and shapes file under root into two graphs."""
    onto, shapes = Graph(), Graph()
    files = sorted(glob.glob(os.path.join(root, ONTOLOGY_GLOB)))
    if not files:
        sys.stderr.write(
            "ERROR: no ontology files matched %s under %s\n" % (ONTOLOGY_GLOB, root)
        )
        sys.exit(2)
    for path in files:
        target = shapes if path.endswith(".shapes.ttl") else onto
        target.parse(path, format="turtle")
    return onto, shapes, files


def qname(term):
    """Render a Cascade term as prefix:Local, anything else as its full IRI."""
    text = str(term)
    if text.startswith(CASCADE_NS_PREFIX):
        rest = text[len(CASCADE_NS_PREFIX):]
        vocab, _, local = rest.partition("#")
        vocab = vocab.split("/")[0]
        prefix = "cascade" if vocab == "core" else vocab
        return "%s:%s" % (prefix, local)
    return "<%s>" % text


# ---------------------------------------------------------------------------
# Graph facts
# ---------------------------------------------------------------------------

def superclass_edges(onto):
    """direct[c] = set of classes c is declared a direct subclass of."""
    direct = {}
    for sub, sup in onto.subject_objects(RDFS.subClassOf):
        if isinstance(sub, URIRef) and isinstance(sup, URIRef):
            direct.setdefault(sub, set()).add(sup)
    return direct


def proper_superclasses(cls, direct):
    """Transitive closure of rdfs:subClassOf, excluding cls itself."""
    seen, stack = set(), list(direct.get(cls, ()))
    while stack:
        node = stack.pop()
        if node not in seen and node != cls:
            seen.add(node)
            stack.extend(direct.get(node, ()))
    return seen


def declared_classes(onto):
    return {
        c
        for c in set(onto.subjects(RDF.type, OWL.Class))
        | set(onto.subjects(RDF.type, RDFS.Class))
        if isinstance(c, URIRef)
    }


def target_index(shapes):
    """by_class[C] = set of shapes that give C an explicit class target.

    Covers sh:targetClass and SHACL's implicit class targets (§2.1.3.3): a
    shape that is itself declared an rdfs:Class or owl:Class targets its own
    instances. Both are explicit in the sense that matters here, because both
    are stated in the shapes graph rather than reached by inference.
    """
    by_class = {}
    for shape, cls in shapes.subject_objects(SH.targetClass):
        if isinstance(cls, URIRef):
            by_class.setdefault(cls, set()).add(shape)
    for shape in set(shapes.subjects(RDF.type, SH.NodeShape)):
        if not isinstance(shape, URIRef):
            continue
        if (shape, RDF.type, RDFS.Class) in shapes or (shape, RDF.type, OWL.Class) in shapes:
            by_class.setdefault(shape, set()).add(shape)
    return by_class


def constraint_sites(shapes):
    """Yield (holder, {sh:class values reachable at that site}).

    A "site" is one constraint holder: a node shape, or the value of one
    sh:property. sh:or / sh:and / sh:xone list members belong to the same site,
    because a value satisfying any listed alternative satisfies the site.
    sh:not is skipped: negation inverts the argument, so downward closure does
    not apply to it.
    """
    holders = set(shapes.subjects(SH.property, None))
    holders |= set(shapes.objects(None, SH.property))
    for holder in holders:
        values = set()
        seen = set()
        stack = [holder]
        while stack:
            node = stack.pop()
            if node in seen:
                continue
            seen.add(node)
            for cls in shapes.objects(node, SH["class"]):
                if isinstance(cls, URIRef):
                    values.add(cls)
            for combinator in (SH["or"], SH["and"], SH.xone):
                for lst in shapes.objects(node, combinator):
                    stack.extend(shapes.items(lst))
        if values:
            yield holder, values


# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

def assert_target_closure(classes, direct, targets):
    """T: a class under a targeted superclass must itself be targeted."""
    examined, findings = 0, []
    for cls in sorted(classes, key=str):
        supers = proper_superclasses(cls, direct)
        targeted_supers = supers & set(targets)
        if not targeted_supers:
            continue
        examined += 1
        if cls not in targets:
            findings.append(
                "%s has no sh:targetClass but inherits from shaped %s"
                % (qname(cls), ", ".join(sorted(qname(s) for s in targeted_supers)))
            )
    return examined, findings


def assert_constraint_equivalence(classes, direct, targets, shapes):
    """I: the constraint set must not depend on the target set expanding."""
    examined, findings = 0, []
    for cls in sorted(classes, key=str):
        if cls not in targets:
            continue
        for sup in sorted(proper_superclasses(cls, direct), key=str):
            if sup not in targets:
                continue
            examined += 1
            super_shapes = targets[sup]
            satisfied = False
            for shape in targets[cls]:
                if shape in super_shapes:
                    satisfied = True  # one shape targets both
                    break
                referenced = set(shapes.objects(shape, SH.node))
                if referenced & super_shapes:
                    satisfied = True  # explicit sh:node reference
                    break
            if not satisfied:
                findings.append(
                    "%s is targeted, and so is its superclass %s, but no shape "
                    "targeting %s reaches %s's constraints via sh:node "
                    "(entailing validators would apply them, others would not)"
                    % (qname(cls), qname(sup), qname(cls), qname(sup))
                )
    return examined, findings


def assert_value_class_closure(direct, shapes):
    """C: the classes accepted at one sh:class site must be downward closed."""
    subclasses = {}
    for sub, sups in direct.items():
        for sup in sups:
            subclasses.setdefault(sup, set()).add(sub)

    def descendants(cls):
        out, stack = set(), list(subclasses.get(cls, ()))
        while stack:
            node = stack.pop()
            if node not in out:
                out.add(node)
                stack.extend(subclasses.get(node, ()))
        return out

    examined, findings = 0, []
    for holder, accepted in constraint_sites(shapes):
        examined += 1
        missing = set()
        for cls in accepted:
            missing |= descendants(cls) - accepted
        if missing:
            paths = sorted(qname(p) for p in shapes.objects(holder, SH.path))
            where = paths[0] if paths else "(node shape)"
            findings.append(
                "sh:class site on %s accepts %s but not its subclass(es) %s "
                "(enumerate them with sh:or)"
                % (
                    where,
                    ", ".join(sorted(qname(a) for a in accepted)),
                    ", ".join(sorted(qname(m) for m in missing)),
                )
            )
    return examined, findings


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ".."
    )
    root = os.path.abspath(root)

    onto, shapes, files = load(root)
    classes = declared_classes(onto)
    direct = superclass_edges(onto)
    targets = target_index(shapes)

    print("Entailment-independence check (see validation/index.md)")
    print("  root:              %s" % root)
    print("  files parsed:      %d" % len(files))
    print("  classes declared:  %d" % len(classes))
    print("  classes targeted:  %d" % len(targets))
    print("  subclass edges:    %d" % sum(len(v) for v in direct.values()))
    print()

    results = [
        ("T  target closure", assert_target_closure(classes, direct, targets)),
        (
            "I  constraint-set equivalence",
            assert_constraint_equivalence(classes, direct, targets, shapes),
        ),
        ("C  value-class closure", assert_value_class_closure(direct, shapes)),
    ]

    failed = 0
    empty = 0
    for name, (examined, findings) in results:
        if examined == 0:
            empty += 1
            print("EMPTY %s: examined 0 cases; this proves nothing" % name)
            continue
        if findings:
            failed += 1
            print("FAIL  %s: %d finding(s) over %d case(s) examined"
                  % (name, len(findings), examined))
            for finding in findings:
                print("        %s" % finding)
        else:
            print("PASS  %s: %d case(s) examined" % (name, examined))

    print()
    if empty:
        print("RESULT: FAIL, %d assertion(s) examined nothing." % empty)
        print("A check with no material to inspect has not verified anything.")
        return 1
    if failed:
        print("RESULT: FAIL, %d of %d assertion(s) failed." % (failed, len(results)))
        print("Shapes must behave identically in an entailing and a non-entailing")
        print("validator. See validation/index.md for the rule and the fix.")
        return 1
    print("RESULT: PASS, %d of %d assertion(s) hold." % (len(results), len(results)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
