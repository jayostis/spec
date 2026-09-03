#!/usr/bin/env python3
"""check-class-coverage.py: a class that can hold record data must be a class
some shape will judge.

THE RULE

A class declaring rdfs:subClassOf prov:Entity or rdfs:subClassOf prov:Activity
has said what it is: a thing instances of which are record data. If no shape
names it in sh:targetClass, then a record of that class is judged by nothing,
and SHACL reports conforms:true over it. That verdict is indistinguishable from
one earned by satisfying every constraint. It is the most expensive kind of
green: a validator ran, said yes, and had looked at nothing.

clinical:CoverageRecord is the worked example. Deprecated in favour of
coverage:InsurancePlan but deliberately RETAINED for EHR-imported data, it went
its entire life with no shape. conformance recorded the symptom locally
(KNOWN_FAILURES.json, "UNSHAPED, ownedBy: spec"), sdk-typescript recorded a
different symptom of the same gap in a source comment, and neither referenced the
other because nothing in this repository asked the question they were both
answers to. clinical v1.18 shaped it; this check is what stops the next one.

WHY check-shape-targets.py DOES NOT COVER THIS, AND MUST NOT BE MADE TO

That script enforces ENTAILMENT INDEPENDENCE: a shape must not reach a class
through rdfs:subClassOf, because SHACL resolves class membership over the data
graph and pod records carry no schema axioms. Its T assertion is conditional by
design -- it fires only when a class has a proper superclass THAT SOME SHAPE
ALREADY TARGETS. Almost every record class here is rdfs:subClassOf prov:Entity
and no shape targets prov:Entity, so T never fires and the script is correctly
silent. It reports PASS 3/3 while dozens of classes are unshaped, and it is not
wrong to: that is a different question, and folding this one into it would cost
the entailment guarantee.

So the two checks are deliberately independent, in the same way
check-nested-severity.py is independent of both. Neither can see the others'
defect.

SCOPE, AND WHAT IS DELIBERATELY OUT

A class is in scope when its rdfs:subClassOf CHAIN reaches prov:Entity or
prov:Activity, at any depth. The chain is walked rather than read one step deep,
because subclassing a record class is a normal idiom here and not a corner case:
the six clinical: document subtypes, six health: data classes,
checkup:DailyCheckIn and diabetes:HbA1cResult all reach prov:Entity through an
intermediate Cascade class. diabetes:HbA1cResult is the worked example -- it is
rdfs:subClassOf diabetes:LabResult, which is rdfs:subClassOf prov:Entity, it has
its own properties (diabetes:hba1cValue, diabetes:hba1cMmolMol), and no shape
targets it. A one-step scope reported PASS straight over exactly the vacuous
conforms:true this check was written to catch. Note that validation/index.md's
own rule is what makes the gap real: a parent's shape does NOT reach the child,
so the child is genuinely unjudged rather than covered by inheritance.

Classes with no rdfs:subClassOf at all are still NOT checked: that set mixes
genuine value enumerations (evidence:VerdictValue, diabetes:MealType), which no
shape should target, with genuine record classes (coverage:ClaimRecord,
clinical:ClinicalNarrative), which one should. Separating them means deciding
what those classes ARE, which is a vocabulary judgement and not something a check
can make. This check covers only the classes whose ancestry already declares them
record-bearing, where the answer needs no judgement.

Only Cascade-namespace classes are reported. A class from an imported external
vocabulary is not this repository's to shape.

WHAT COUNTS AS SHAPED

An sh:targetClass on a shape that carries no constraint does not count. This

    ex:FooShape a sh:NodeShape ;
        sh:targetClass ex:Foo .

names the class and asks nothing of it, so SHACL still reports conforms:true over
every ex:Foo record having examined nothing -- which is the defect above, not a
fix for it. A targeting shape must carry at least one SHACL constraint parameter
(sh:property, or a node-level sh:class / sh:in / sh:node / sh:closed / ...) for
the class to count as covered. Without this rule a contributor could clear a
baseline entry, and the ratchet with it, without writing a single constraint.

THE BASELINE

scripts/known-unshaped-classes.json enumerates the unshaped classes that predate
this check. It is a GATE INPUT, not a filter: every class is still examined and
counted. The run fails when

  * a prov-rooted class is unshaped and the baseline does not list it,
  * a baselined class has since been shaped, or
  * a baselined class no longer exists,

which are reported SEPARATELY because they carry different remediations: the
second means a shape was written and the entry should record that, the third
means the class was deleted or renamed and there is no shape to go and find. So
the list can only shrink, and shrinking it is an explicit committed edit.
Every entry names the vocabulary that owns the fix. Nothing in it is acceptable
in the long run: each entry is a class whose records validate vacuously today.

Exit status: 0 if every prov-rooted class is shaped or baselined, 1 on any
finding, and 1 if the run examined no classes at all -- a check with no material
to inspect has proven nothing.

Usage:  python3 scripts/check-class-coverage.py [spec-root] [--no-baseline]

  --no-baseline  ignore the baseline entirely and report every unshaped class.
                 This is how the list is regenerated and how the regression
                 suite proves the baseline is a ratchet rather than a mute
                 switch. It always exits non-zero when anything is unshaped.

Requires: rdflib (see scripts/requirements.txt)
"""

import glob
import json
import os
import sys

try:
    from rdflib import Graph, RDFS, Namespace, URIRef
except ImportError:  # pragma: no cover - environment guard
    sys.stderr.write(
        "ERROR: rdflib is not installed. This check parses Turtle and cannot\n"
        "       degrade to a text scan without becoming unsound.\n"
        "       Install it with:  python3 -m pip install -r scripts/requirements.txt\n"
    )
    sys.exit(2)

SH = Namespace("http://www.w3.org/ns/shacl#")
PROV = Namespace("http://www.w3.org/ns/prov#")
CASCADE_NS_PREFIX = "https://ns.cascadeprotocol.org/"

ONTOLOGY_GLOB = "ontologies/*/v1*/*.ttl"
BASELINE = "scripts/known-unshaped-classes.json"

# The PROV superclasses that declare a class record-bearing. A class asserting
# either has said its instances are data someone stores, which is exactly the
# population a shape is for.
RECORD_ROOTS = (PROV.Entity, PROV.Activity)

# The SHACL core constraint parameters. A shape carrying none of these asks
# nothing of the nodes it targets, so naming a class in its sh:targetClass does
# not make that class judged.
#
# Deliberately a list of constraint parameters rather than "any sh: predicate":
# sh:targetClass, sh:name, sh:message, sh:severity, sh:description, sh:order,
# sh:group, sh:path and sh:deactivated are all sh: predicates that constrain
# nothing, and counting them would restore the loophole under another spelling.
CONSTRAINT_PARAMETERS = frozenset([
    # Value type
    SH["class"], SH.datatype, SH.nodeKind,
    # Cardinality
    SH.minCount, SH.maxCount,
    # Value range
    SH.minExclusive, SH.minInclusive, SH.maxExclusive, SH.maxInclusive,
    # String
    SH.minLength, SH.maxLength, SH.pattern, SH.languageIn, SH.uniqueLang,
    # Property pair
    SH.equals, SH.disjoint, SH.lessThan, SH.lessThanOrEquals,
    # Logical
    SH["not"], SH["and"], SH["or"], SH.xone,
    # Shape-based
    SH.node, SH.property, SH.qualifiedValueShape,
    # Other
    SH.closed, SH.hasValue, SH["in"], SH.sparql,
])


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


def is_cascade(term):
    return str(term).startswith(CASCADE_NS_PREFIX)


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def load(root):
    """Parse ontologies and shapes into SEPARATE graphs.

    They must stay separate. sh:targetClass is a fact about the shapes graph and
    rdfs:subClassOf a fact about the ontology graph; merging them would not
    change this check's answer today, but it would make it possible to write one
    that reads a shape's target out of an ontology file, which is the confusion
    check-shape-targets.py exists to prevent.
    """
    ontology, shapes = Graph(), Graph()
    onto_files, shape_files = [], []
    for path in sorted(glob.glob(os.path.join(root, ONTOLOGY_GLOB))):
        if path.endswith(".shapes.ttl"):
            shapes.parse(path, format="turtle")
            shape_files.append(path)
        else:
            ontology.parse(path, format="turtle")
            onto_files.append(path)
    if not onto_files:
        sys.stderr.write(
            "ERROR: no ontology files matched %s under %s\n" % (ONTOLOGY_GLOB, root)
        )
        sys.exit(2)
    if not shape_files:
        sys.stderr.write(
            "ERROR: no shapes files matched %s under %s. Without them every\n"
            "       class would look unshaped and the run would be meaningless.\n"
            % (ONTOLOGY_GLOB, root)
        )
        sys.exit(2)
    return ontology, shapes, onto_files, shape_files


# ---------------------------------------------------------------------------
# Graph facts
# ---------------------------------------------------------------------------

def superclass_edges(ontology):
    """direct[c] = the classes c is declared a DIRECT rdfs:subClassOf of.

    Blank-node superclasses (owl:Restriction and friends) are dropped: they are
    not classes this check can ask anyone to shape, and they cannot lead to
    prov:Entity by a named edge.
    """
    direct = {}
    for sub_, sup in ontology.subject_objects(RDFS.subClassOf):
        if isinstance(sub_, URIRef) and isinstance(sup, URIRef):
            direct.setdefault(sub_, set()).add(sup)
    return direct


def reaches_record_root(cls, direct):
    """True if cls reaches prov:Entity or prov:Activity by any number of
    rdfs:subClassOf steps. Cycles terminate: a node is expanded once."""
    seen, stack = set(), list(direct.get(cls, ()))
    while stack:
        node = stack.pop()
        if node in RECORD_ROOTS:
            return True
        if node not in seen:
            seen.add(node)
            stack.extend(direct.get(node, ()))
    return False


def record_bearing_classes(ontology):
    """Cascade classes whose rdfs:subClassOf CHAIN reaches a PROV record root.

    Transitive, not one step: see SCOPE in the module docstring. A class that
    inherits prov:Entity through an intermediate Cascade class has inherited
    exactly the declaration this check keys on, and identifying it needs no
    vocabulary judgement.
    """
    direct = superclass_edges(ontology)
    return {
        cls for cls in direct
        if is_cascade(cls) and reaches_record_root(cls, direct)
    }


def constrains_anything(shape, shapes):
    """True if `shape` carries at least one SHACL constraint parameter."""
    return any((shape, param, None) in shapes for param in CONSTRAINT_PARAMETERS)


def targeted_classes(shapes):
    """Every class named by an sh:targetClass on a shape that CONSTRAINS it.

    A bare sh:targetClass with no constraint beside it leaves SHACL reporting
    conforms:true over the class's records having examined nothing, which is the
    condition this check reports rather than a remedy for it.
    """
    return {
        cls for shape, cls in shapes.subject_objects(SH.targetClass)
        if constrains_anything(shape, shapes)
    }


# ---------------------------------------------------------------------------
# Baseline
# ---------------------------------------------------------------------------

def load_baseline(root):
    path = os.path.join(root, BASELINE)
    if not os.path.exists(path):
        sys.stderr.write(
            "ERROR: baseline %s not found. It is a required input: without it\n"
            "       this check cannot tell a pre-existing gap from a new one.\n"
            "       Run with --no-baseline to see the full list.\n" % BASELINE
        )
        sys.exit(2)
    with open(path, "r", encoding="utf-8") as handle:
        doc = json.load(handle)
    return {entry["class"]: entry for entry in doc.get("entries", [])}


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main():
    args = [a for a in sys.argv[1:]]
    use_baseline = "--no-baseline" not in args
    args = [a for a in args if a != "--no-baseline"]
    root = args[0] if args else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ".."
    )
    root = os.path.abspath(root)

    ontology, shapes, onto_files, shape_files = load(root)
    record_classes = record_bearing_classes(ontology)
    targeted = targeted_classes(shapes)
    unshaped = sorted(qname(c) for c in record_classes - targeted)

    baseline = load_baseline(root) if use_baseline else {}

    print("Record-class shape coverage check")
    print("  root:              %s" % root)
    print("  ontologies parsed: %d" % len(onto_files))
    print("  shapes parsed:     %d" % len(shape_files))
    print("  record classes:    %d  (rdfs:subClassOf* prov:Entity | prov:Activity)"
          % len(record_classes))
    print("  shaped:            %d" % (len(record_classes) - len(unshaped)))
    print("  unshaped:          %d" % len(unshaped))
    if use_baseline:
        print("  baselined:         %d" % len(baseline))
    else:
        print("  baselined:         (ignored, --no-baseline)")
    print()

    if not record_classes:
        print("EMPTY: no class declares a PROV record superclass.")
        print("A check with no material to inspect has not verified anything.")
        return 1

    if not use_baseline:
        if unshaped:
            print("FAIL  %d unshaped record class(es):" % len(unshaped))
            for name in unshaped:
                print("        %s" % name)
            print()
            print("RESULT: FAIL")
            return 1
        print("RESULT: PASS, every record class is targeted by some shape.")
        return 0

    new = [name for name in unshaped if name not in baseline]

    # A baselined class that is no longer unshaped is one of two different
    # events, and only one of them is about a shape. Splitting them here is what
    # lets each carry its own remediation: telling a reader to go and find the
    # shape that fixed a class someone DELETED sends them looking for something
    # nobody ever wrote.
    live = {qname(cls) for cls in record_classes}
    settled = sorted(set(baseline) - set(unshaped))
    stale_shaped = [name for name in settled if name in live]
    stale_gone = [name for name in settled if name not in live]

    if new:
        print("FAIL  %d unbaselined unshaped record class(es):" % len(new))
        for name in new:
            print("        %s" % name)
        print()
        print("      A class whose rdfs:subClassOf chain reaches prov:Entity or")
        print("      prov:Activity holds record data, and no shape names it in")
        print("      sh:targetClass with a constraint beside it, so SHACL reports")
        print("      conforms:true over its records having examined nothing. Give it")
        print("      a shape -- its OWN sh:targetClass, since a parent shape does not")
        print("      reach it -- or, if it genuinely holds no record data, reconsider")
        print("      the PROV superclass, which is what declares that it does.")
        print()

    if stale_shaped:
        print("FAIL  %d baselined class(es) no longer unshaped:" % len(stale_shaped))
        for name in stale_shaped:
            print("        %s" % name)
        print()
        print("      This is good news that must be recorded: a shape now judges the")
        print("      class, so remove the entry from")
        print("      %s. The baseline keeps" % BASELINE)
        print("      matching reality and cannot silently re-absorb the class later.")
        print()

    if stale_gone:
        print("FAIL  %d baselined class(es) no longer exist:" % len(stale_gone))
        for name in stale_gone:
            print("        %s" % name)
        print()
        print("      These are NOT shaped -- the class was deleted, renamed, or moved")
        print("      out of the ontology tree, so there is no shape to go and find.")
        print("      Remove the entry from")
        print("      %s, and if the class was" % BASELINE)
        print("      renamed rather than dropped, add the new name in its place: the")
        print("      gap moved with it.")
        print()

    if new or stale_shaped or stale_gone:
        print("RESULT: FAIL")
        return 1

    print("RESULT: PASS, %d record class(es) examined, %d shaped, %d baselined "
          "and unchanged." % (len(record_classes),
                              len(record_classes) - len(unshaped),
                              len(baseline)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
