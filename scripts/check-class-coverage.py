#!/usr/bin/env python3
"""check-class-coverage.py: a class that can hold record data must be a class
some shape will judge.

THE RULE

A class declaring `a cascade:RecordClass` has said what it is: a thing instances
of which are stored record data. If no shape names it in sh:targetClass, then a
record of that class is judged by nothing, and SHACL reports conforms:true over
it. That verdict is indistinguishable from one earned by satisfying every
constraint. It is the most expensive kind of green: a validator ran, said yes,
and had looked at nothing.

WHAT THIS CHECK USED TO KEY ON, AND WHY IT NO LONGER DOES

Through core v3.12 this script keyed on rdfs:subClassOf prov:Entity /
prov:Activity, on the reading that the axiom asserts a class bears record data.
jayostis/spec#34 (ASK-05) ruled that reading out:

  "The reading 'subClassOf prov:Entity means instances are stored record data'
   is not the intent. The axiom is PROV-O alignment ... Your shape-coverage
   checker should key on that, or on an explicit list, never on prov:Entity,
   which will keep catching alignment axioms."

Measured at the time of the change: 110 classes reached a PROV root, of which 96
were registered nowhere as stored records -- alignment axioms, exactly as
predicted. core v3.13 declares cascade:RecordClass as the explicit designation
and 83 classes carry it.

DO NOT REINTRODUCE ANY rdfs:subClassOf READING HERE. A PROV superclass is
alignment and confers nothing; a class may carry the marker with no PROV
superclass at all, and several do. test-record-class-declarations.sh asserts
this directly: it adds prov:Entity to an unmarked scratch class and requires the
population NOT to move.

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
ALREADY TARGETS. Many record classes here are rdfs:subClassOf prov:Entity
and no shape targets prov:Entity, so T rarely fires and the script is correctly
silent. It reports PASS 3/3 while dozens of classes are unshaped, and it is not
wrong to: that is a different question, and folding this one into it would cost
the entailment guarantee.

So the two checks are deliberately independent, in the same way
check-nested-severity.py is independent of both. Neither can see the others'
defect.

SCOPE, AND WHAT IS DELIBERATELY OUT

A class is in scope when it carries `a cascade:RecordClass`. Membership is that
triple and nothing else -- not inherited, not inferred, not walked. A subclass of
a marked class is NOT in scope unless it carries its own marker, which is the
same shape as validation/index.md's rule that a parent's shape does not reach a
child: if inheritance does not carry the constraint, it must not carry the
obligation either. The six clinical: document subtypes each carry their own
marker for exactly this reason.

That the population is now an enumeration rather than a derivation is the point,
not a compromise. Deciding what a class IS is a vocabulary judgement, and this
check is not the place to make one -- it reads the judgement the vocabulary has
already recorded. A class that holds record data and lacks the marker is a
vocabulary defect, and the fix is the marker, never a change here.

test-record-class-declarations.sh is the suite that asserts the vocabulary keeps
saying something true about itself, using this script unchanged as the
instrument.

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

  * a marked class is unshaped and the baseline does not list it,
  * a baselined class has since been shaped, or
  * a baselined class no longer exists,

which are reported SEPARATELY because they carry different remediations: the
second means a shape was written and the entry should record that, the third
means the class was deleted or renamed and there is no shape to go and find. So
the list can only shrink, and shrinking it is an explicit committed edit.
Every entry names the vocabulary that owns the fix. Nothing in it is acceptable
in the long run: each entry is a class whose records validate vacuously today.

Exit status: 0 if every marked class is shaped or baselined, 1 on any
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
    from rdflib import Graph, RDF, Namespace, URIRef
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
BASELINE = "scripts/known-unshaped-classes.json"

# The marker that declares a class record-bearing. A class carrying it has said
# its instances are data someone stores, which is exactly the population a shape
# is for. Declared in core v3.13; see the module docstring for why this replaced
# a reading of rdfs:subClassOf prov:Entity, and jayostis/spec#34 for the ruling.
RECORD_CLASS_MARKER = URIRef(CASCADE_NS_PREFIX + "core/v1#RecordClass")

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

def record_bearing_classes(ontology):
    """Cascade classes carrying `a cascade:RecordClass`.

    A direct read of one triple per class. Deliberately NOT transitive and
    deliberately not reading rdfs:subClassOf at all: membership is the explicit
    designation the vocabulary makes, per jayostis/spec#34. A subclass of a
    marked class must carry its own marker, matching validation/index.md's rule
    that a parent's shape does not reach a child.

    cascade:RecordClass itself is excluded. It is the marker, not a record
    class, and nothing marks it -- but excluding it explicitly means a future
    stray triple cannot put the marker into its own population.
    """
    return {
        cls for cls in ontology.subjects(RDF.type, RECORD_CLASS_MARKER)
        if isinstance(cls, URIRef)
        and is_cascade(cls)
        and cls != RECORD_CLASS_MARKER
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
    print("  record classes:    %d  (a cascade:RecordClass)"
          % len(record_classes))
    print("  shaped:            %d" % (len(record_classes) - len(unshaped)))
    print("  unshaped:          %d" % len(unshaped))
    if use_baseline:
        print("  baselined:         %d" % len(baseline))
    else:
        print("  baselined:         (ignored, --no-baseline)")
    print()

    if not record_classes:
        print("EMPTY: no class carries a cascade:RecordClass marker.")
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
        print("      A class carrying a cascade:RecordClass marker holds record")
        print("      data, and no shape names it in")
        print("      sh:targetClass with a constraint beside it, so SHACL reports")
        print("      conforms:true over its records having examined nothing. Give it")
        print("      a shape -- its OWN sh:targetClass, since a parent shape does not")
        print("      reach it -- or, if it genuinely holds no record data, remove")
        print("      the cascade:RecordClass marker, which is what declares it does.")
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
