#!/usr/bin/env python3
"""check-nested-severity.py: no shape referenced as a nested shape may carry a
constraint softer than sh:Violation.

THE RULE

SHACL defines conformance as an EMPTY validation result
(https://www.w3.org/TR/shacl/#conformance-checking). That definition does not
consult severity. So when a constraint is expressed as "this node conforms to
shape S" -- sh:node, or sh:qualifiedValueShape -- a nested sh:Warning inside S is
still a result, the node therefore does not conform, and the REFERRING constraint
reports a failure at ITS OWN severity, which is sh:Violation unless something
declares otherwise.

The consequence is that publishing a Warning on a shape that anything reaches by
sh:node silently republishes it as a Violation on every referring class, and the
nested result may not be surfaced at all: the reader gets an opaque
sh:NodeConstraintComponent naming no field.

That is not a hypothetical. clinical v1.16 declared the clinical:status and
clinical:documentReferenceStatus value sets at sh:Warning on
clinical:ClinicalDocumentShape, which six document subtype shapes reach through
sh:node. Every one of those six REJECTED a status value the release said would
only be reported, on two independent engines, and on clinical:ProgressNote the
warning was not reported at all. clinical v1.17 fixed it by moving the two
bindings onto shapes that TARGET the classes directly. This check exists so the
class cannot be reintroduced.

WHY sh:severity ON THE REFERRING CONSTRAINT IS NOT THE FIX, AND IS NOT ACCEPTED
HERE: severity attaches to the shape a constraint belongs to, not to one nested
result, so declaring sh:severity sh:Warning beside an sh:node reference demotes
the WHOLE referenced shape -- structural violations included. A shape used as a
nested shape must carry Violation-severity constraints only, and anything softer
belongs on a shape that reaches its classes by sh:targetClass.

WHAT THIS CHECK IS NOT: it is not a SHACL run. It reasons over the shapes graph,
like check-shape-targets.py, and it is deliberately independent of the
entailment question that check covers -- neither one can see the other's defect.

THE BASELINE

scripts/nested-severity-baseline.json enumerates the sites that predate this
check. It is a GATE INPUT, not a filter: every site is still examined and
reported. The run fails when

  * a site is found that the baseline does not list, and
  * a baselined site is no longer found,

so the list can only shrink, and shrinking it is an explicit committed edit.
Every entry names the vocabulary that owns the fix.

Exit status: 0 if every reference is clean or baselined, 1 on any finding, and 1
if the run examined no references at all -- a check with no material to inspect
has proven nothing.

Usage:  python3 scripts/check-nested-severity.py [spec-root]
Requires: rdflib (see scripts/requirements.txt)
"""

import glob
import json
import os
import sys

try:
    from rdflib import Graph, RDF, URIRef, Namespace
except ImportError:  # pragma: no cover - environment guard
    sys.stderr.write(
        "ERROR: rdflib is not installed. This check parses Turtle and cannot\n"
        "       degrade to a text scan without becoming unsound.\n"
        "       Install it with:  python3 -m pip install -r scripts/requirements.txt\n"
    )
    sys.exit(2)

SH = Namespace("http://www.w3.org/ns/shacl#")
CASCADE_NS_PREFIX = "https://ns.cascadeprotocol.org/"

SHAPES_GLOB = "ontologies/*/v1*/*.shapes.ttl"
BASELINE = "scripts/nested-severity-baseline.json"

# The constraint parameters whose value is a SHAPE the focus/value node must
# CONFORM TO. These are the ones that collapse a nested result set to a boolean
# and re-report it at the referring shape's severity.
NESTED_SHAPE_PARAMS = (SH.node, SH.qualifiedValueShape)

# Every way a result produced inside a shape is attributed to that shape. Used
# to decide which severities are reachable from a referenced shape.
CONTAINMENT_PARAMS = (SH.property, SH.node, SH.qualifiedValueShape, SH["not"])
CONTAINMENT_LISTS = (SH["or"], SH["and"], SH.xone)

SOFT_SEVERITIES = {SH.Warning: "sh:Warning", SH.Info: "sh:Info"}


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
# Loading
# ---------------------------------------------------------------------------

def load(root):
    graph = Graph()
    files = sorted(glob.glob(os.path.join(root, SHAPES_GLOB)))
    if not files:
        sys.stderr.write(
            "ERROR: no shapes files matched %s under %s\n" % (SHAPES_GLOB, root)
        )
        sys.exit(2)
    for path in files:
        graph.parse(path, format="turtle")
    return graph, files


# ---------------------------------------------------------------------------
# Graph facts
# ---------------------------------------------------------------------------

def reachable_severities(graph, shape):
    """Severities of every constraint whose result is attributed to `shape`.

    Follows sh:property into property shapes, and the nested-shape parameters
    onward, because a Warning two levels down escalates just the same: the
    intermediate shape is made non-conforming by it and the escalation
    propagates outward.
    """
    severities = set()
    seen = set()
    stack = [shape]
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        for sev in graph.objects(node, SH.severity):
            severities.add(sev)
        for param in CONTAINMENT_PARAMS:
            stack.extend(graph.objects(node, param))
        for param in CONTAINMENT_LISTS:
            for lst in graph.objects(node, param):
                stack.extend(graph.items(lst))
    return severities


def site_label(graph, referrer):
    """A stable, human-readable name for the place a reference is written.

    An IRI shape names itself. A blank-node property shape is named by the
    nearest IRI ancestor plus its sh:path, which is what a reader would use to
    find it and what survives reformatting of the file.
    """
    if isinstance(referrer, URIRef):
        return qname(referrer)

    seen = set()
    stack = [referrer]
    path_terms = sorted(qname(p) for p in graph.objects(referrer, SH.path))
    while stack:
        node = stack.pop()
        if node in seen:
            continue
        seen.add(node)
        for param in CONTAINMENT_PARAMS + CONTAINMENT_LISTS:
            for owner in graph.subjects(param, node):
                if isinstance(owner, URIRef):
                    where = " [%s]" % ", ".join(path_terms) if path_terms else " [anonymous]"
                    return qname(owner) + where
                stack.append(owner)
            # list membership: the owner points at a list containing this node
        for lst in graph.subjects(RDF.first, node):
            stack.append(lst)
        for lst in graph.subjects(RDF.rest, node):
            stack.append(lst)
    return "(unattached blank shape)%s" % (
        " [%s]" % ", ".join(path_terms) if path_terms else ""
    )


def findings(graph):
    """Yield (key, referrer_label, param, referenced, severities) per bad site."""
    out = []
    examined = 0
    for param in NESTED_SHAPE_PARAMS:
        param_name = qname(param) if str(param).startswith(CASCADE_NS_PREFIX) else "sh:" + str(param).split("#")[-1]
        for referrer, referenced in graph.subject_objects(param):
            examined += 1
            soft = reachable_severities(graph, referenced) & set(SOFT_SEVERITIES)
            if not soft:
                continue
            label = site_label(graph, referrer)
            key = "%s %s %s" % (label, param_name, qname(referenced))
            out.append(
                {
                    "site": key,
                    "carries": sorted(SOFT_SEVERITIES[s] for s in soft),
                }
            )
    # Deterministic order, and de-duplicated: the same site may be reached twice
    # when a shape is referenced from more than one place under one label.
    unique = {}
    for item in out:
        unique.setdefault(item["site"], item)
    return examined, [unique[k] for k in sorted(unique)]


# ---------------------------------------------------------------------------
# Baseline
# ---------------------------------------------------------------------------

def load_baseline(root):
    path = os.path.join(root, BASELINE)
    if not os.path.exists(path):
        sys.stderr.write(
            "ERROR: baseline %s not found. It is a required input: without it\n"
            "       this check cannot tell a pre-existing site from a new one.\n"
            % BASELINE
        )
        sys.exit(2)
    with open(path, "r", encoding="utf-8") as handle:
        doc = json.load(handle)
    return {entry["site"]: entry for entry in doc.get("entries", [])}


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ".."
    )
    root = os.path.abspath(root)

    graph, files = load(root)
    baseline = load_baseline(root)
    examined, found = findings(graph)
    found_keys = {item["site"] for item in found}

    print("Nested-shape severity check")
    print("  root:              %s" % root)
    print("  shapes parsed:     %d" % len(files))
    print("  references seen:   %d  (sh:node, sh:qualifiedValueShape)" % examined)
    print("  sites carrying sh:Warning / sh:Info: %d" % len(found))
    print("  baselined:         %d" % len(baseline))
    print()

    if examined == 0:
        print("EMPTY: no sh:node or sh:qualifiedValueShape reference was found.")
        print("A check with no material to inspect has not verified anything.")
        return 1

    new = [item for item in found if item["site"] not in baseline]
    stale = sorted(set(baseline) - found_keys)

    if new:
        print("FAIL  %d unbaselined site(s):" % len(new))
        for item in new:
            print("        %s" % item["site"])
            print("          carries %s" % ", ".join(item["carries"]))
        print()
        print("      A nested shape's sh:Warning / sh:Info is reported as a")
        print("      sh:Violation on the referring shape, because SHACL conformance")
        print("      is an empty result set. Move the soft constraint onto a shape")
        print("      that reaches its classes by sh:targetClass. Do NOT declare")
        print("      sh:severity on the reference: that demotes the whole")
        print("      referenced shape, structural violations included.")
        print()

    if stale:
        print("FAIL  %d baselined site(s) no longer present:" % len(stale))
        for site in stale:
            print("        %s" % site)
        print()
        print("      This is good news that must be recorded: remove the entry from")
        print("      %s so the baseline keeps" % BASELINE)
        print("      matching reality and cannot silently re-absorb the site later.")
        print()

    if new or stale:
        print("RESULT: FAIL")
        return 1

    print("RESULT: PASS, %d reference(s) examined, %d baselined and unchanged."
          % (examined, len(baseline)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
