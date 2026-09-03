"""cascade_ontology.py: the ontology corpus, read in one place.

NOT A CHECK. This module holds what "the ontologies" MEANS for the checks in
this directory: which files are in the corpus, which are excluded, and how they
are parsed. It is imported, never run.

WHY IT EXISTS

check-record-class-registry.py and check-context-coverage.py both compare the
marked record classes against a second artifact -- pod-structure.md's
solid:forClass registrations, and the published JSON-LD contexts -- and each
carried a byte-for-byte copy of the loader. Two copies of a definition are two
things that can drift: the `.shapes.ttl` exclusion, or the glob's `v1*`, could
change in one and not the other, and both checks would go on reporting
"ontologies parsed: N" as though they had read the same corpus. Comparing two
enumerations of the same fact is the entire value of both checks, so which
files they enumerate is not an implementation detail either of them owns.

THE EXCLUSION IS LOAD-BEARING, NOT TIDINESS

ONTOLOGY_GLOB matches *.ttl, which includes the *.shapes.ttl files beside each
ontology, and those are skipped. Merging shapes into the ontology graph would
make `sh:targetClass` readable as though it were an ontology fact -- the exact
confusion check-shape-targets.py exists to prevent -- and it would put every
shapes file's @prefix declarations into the namespace table that
check-record-class-registry.py resolves registrations against.

Requires: rdflib (see scripts/requirements.txt)
"""

import glob
import os
import sys

try:
    from rdflib import Graph
except ImportError:  # pragma: no cover - environment guard
    sys.stderr.write(
        "ERROR: rdflib is not installed. These checks parse Turtle and cannot\n"
        "       degrade to a text scan without becoming unsound.\n"
        "       Install it with:  python3 -m pip install -r scripts/requirements.txt\n"
    )
    sys.exit(2)

from rdflib import URIRef  # noqa: E402  (guarded by the import above)

CASCADE_NS_PREFIX = "https://ns.cascadeprotocol.org/"

# The marker that declares a class record-bearing: its instances are data a Pod
# stores. Declared in core v1; jayostis/spec#34 ruled out deriving it from
# rdfs:subClassOf prov:Entity, which is PROV-O alignment.
RECORD_CLASS_MARKER = URIRef(CASCADE_NS_PREFIX + "core/v1#RecordClass")

ONTOLOGY_GLOB = "ontologies/*/v1*/*.ttl"


def load_ontology(root):
    """(graph, files) for every ontology under root, shapes files excluded.

    Exits 2 rather than returning an empty graph when nothing matched: a check
    that compares an empty corpus to anything reports agreement it never
    tested, which is indistinguishable from an earned pass.
    """
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


def spec_root(argv):
    """The spec root: argv[0] if given, else the parent of scripts/."""
    if argv:
        return os.path.abspath(argv[0])
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
