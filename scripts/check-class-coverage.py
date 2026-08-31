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

Only classes with a DIRECT rdfs:subClassOf prov:Entity / prov:Activity are
required to be shaped. Classes with no rdfs:subClassOf at all are NOT checked:
that set mixes genuine value enumerations (evidence:VerdictValue,
diabetes:MealType), which no shape should target, with genuine record classes
(coverage:ClaimRecord, clinical:ClinicalNarrative), which one should. Separating
them means deciding what those classes ARE, which is a vocabulary judgement and
not something a check can make. This check covers only the classes whose own PROV
superclass already declares them record-bearing, where the answer needs no
judgement.

Only Cascade-namespace classes are reported. A class from an imported external
vocabulary is not this repository's to shape.

THE BASELINE

scripts/class-coverage-baseline.json enumerates the unshaped classes that predate
this check. It is a GATE INPUT, not a filter: every class is still examined and
counted. The run fails when

  * a prov-rooted class is unshaped and the baseline does not list it, and
  * a baselined class is no longer unshaped, or no longer exists,

so the list can only shrink, and shrinking it is an explicit committed edit.
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
    from rdflib import Graph, RDFS, Namespace
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
BASELINE = "scripts/class-coverage-baseline.json"

# The PROV superclasses that declare a class record-bearing. A class asserting
# either has said its instances are data someone stores, which is exactly the
# population a shape is for.
RECORD_ROOTS = (PROV.Entity, PROV.Activity)


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
    """Cascade classes directly declaring a PROV record superclass."""
    out = set()
    for root_class in RECORD_ROOTS:
        for subject in ontology.subjects(RDFS.subClassOf, root_class):
            if is_cascade(subject):
                out.add(subject)
    return out


def targeted_classes(shapes):
    """Every class named by some sh:targetClass, anywhere in the shapes graph."""
    return set(shapes.objects(None, SH.targetClass))


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
    print("  record classes:    %d  (rdfs:subClassOf prov:Entity | prov:Activity)"
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
    stale = sorted(set(baseline) - set(unshaped))

    if new:
        print("FAIL  %d unbaselined unshaped record class(es):" % len(new))
        for name in new:
            print("        %s" % name)
        print()
        print("      A class declaring rdfs:subClassOf prov:Entity or prov:Activity")
        print("      holds record data, and no shape names it in sh:targetClass, so")
        print("      SHACL reports conforms:true over its records having examined")
        print("      nothing. Give it a shape, or -- if it genuinely holds no record")
        print("      data -- reconsider the PROV superclass, which is what declares")
        print("      that it does.")
        print()

    if stale:
        print("FAIL  %d baselined class(es) no longer unshaped:" % len(stale))
        for name in stale:
            print("        %s" % name)
        print()
        print("      This is good news that must be recorded: remove the entry from")
        print("      %s so the baseline keeps" % BASELINE)
        print("      matching reality and cannot silently re-absorb the class later.")
        print()

    if new or stale:
        print("RESULT: FAIL")
        return 1

    print("RESULT: PASS, %d record class(es) examined, %d shaped, %d baselined "
          "and unchanged." % (len(record_classes),
                              len(record_classes) - len(unshaped),
                              len(baseline)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
