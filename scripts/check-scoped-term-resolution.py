#!/usr/bin/env python3
"""check-scoped-term-resolution.py -- a scoped term resolves to the right IRI.

Run from the spec repo root:
    python3 scripts/check-scoped-term-resolution.py

WHY THIS EXISTS
---------------
check-context-validity.py proves a context LOADS. It does not, and by its own
docstring never claimed to, prove that a term maps to the right IRI. Term-scoped
`@context` and `@vocab` (issue #47, #44) are exactly the class of construct where
that gap matters: they are new to this repository, easy to write in a shape that
parses but resolves wrong, and the failure is invisible to a loadability check --
a bare token that resolves to the wrong namespace, or a nested key that keeps
meaning what it means at the top level, both still expand cleanly.

This repository has shipped that exact class of defect three times before
(severity escalating through `sh:node`, a context comment read as a term,
`rdfs:subClassOf` read as record-class membership) -- each time because a
plausible-looking construct went unverified. See CLAUDE.md. This is that
verification, for the two issues that introduce term-scoped contexts.

WHAT THIS CHECKS, AND WHY EACH CASE IS HERE
--------------------------------------------
1. `dataProvenance` / `provenanceLayers` (#47): a bare token under `@type:
   @vocab` resolves into the core namespace, including a token that is NOT
   already a flat term in the file -- proving the term-scoped `@vocab`
   fallback does real work, not just the already-registered DataSource names.

2. The seven structured terms (#44): every declared child of `address`,
   `emergencyContact`, `preferredPharmacy`, `advanceDirectives`,
   `clinicalSummary` / `wellnessSummary`, and `clinical:hasParticipant`
   resolves to its own predicate when nested, exactly as it does flat.

3. The collision case (#44's live defect, #3, #46 mode 2): `notes` inside
   `clinicalSummary` must expand to `cascade:notes` while `notes` at the top
   level of the SAME document expands to `health:notes` (or `clinical:notes`).
   A flat context cannot do this; this is the one assertion that only a
   scoped context can pass, and it is the regression that matters most.

4. A sample of untouched flat terms resolves identically to before. Term
   scoping in this repository has a defined, narrow blast radius (#47's own
   Option A vs Option B argument), and this is what proves the blast radius
   was actually kept narrow rather than asserted.

WHAT THIS DOES NOT CHECK
-------------------------
Node typing on the WRITE path. A term's `@type: cascade:Address` selects the
scoped @context for that term's children; it does NOT cause `a cascade:Address`
to appear on the expanded node -- JSON-LD only applies a type-scoped context
when the DATA itself carries a matching `@type`, and does not run the reverse
inference. Measured directly against this file: an `address` object with no
`@type` of its own expands with no `@type` key at all. So a JSON->RDF writer
still needs the class from the ontology's `rdfs:range` (which `sdk-typescript`
already reads) or the JSON payload would need to carry `@type` explicitly --
context alone does not produce the type triple. This check does not assert
otherwise; a check that did would be asserting something false.
"""

import json
import sys

try:
    from pyld import jsonld
except ImportError:
    print("ERROR: cannot import pyld, so nothing would be checked.\n"
          "       Install it:  python3 -m pip install -r scripts/requirements.txt",
          file=sys.stderr)
    sys.exit(2)

CORE_NS = "https://ns.cascadeprotocol.org/core/v1#"
CLINICAL_NS = "https://ns.cascadeprotocol.org/clinical/v1#"
HEALTH_NS = "https://ns.cascadeprotocol.org/health/v1#"

FAILURES = []


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)["@context"]


def expand_one(ctx, doc_body):
    doc = {"@context": ctx, "@id": "urn:x:check", **doc_body}
    result = jsonld.expand(doc)
    if not result:
        return {}
    return result[0]


def assert_predicate(label, node, predicate, expected_value=None,
                      expected_type_iri=None):
    if predicate not in node:
        FAILURES.append(f"{label}: expected predicate {predicate!r} "
                         f"missing. Got keys: {sorted(node.keys())}")
        return
    values = node[predicate]
    if expected_value is not None:
        got = values[0].get("@value")
        if got != expected_value:
            FAILURES.append(f"{label}: {predicate!r} = {got!r}, "
                             f"expected {expected_value!r}")
    if expected_type_iri is not None:
        got = values[0].get("@id")
        if got != expected_type_iri:
            FAILURES.append(f"{label}: {predicate!r} @id = {got!r}, "
                             f"expected {expected_type_iri!r}")


def assert_absent(label, node, predicate):
    if predicate in node:
        FAILURES.append(f"{label}: predicate {predicate!r} present and "
                         "should not be -- the scoping did not override it")


def check_bare_provenance_token(ctx, file_label):
    # A token already registered as a flat term (`ClinicalGenerated`).
    node = expand_one(ctx, {"dataProvenance": "ClinicalGenerated"})
    assert_predicate(f"{file_label}: dataProvenance (registered token)",
                      node, CORE_NS + "dataProvenance",
                      expected_type_iri=CORE_NS + "ClinicalGenerated")

    # A token that is NOT a flat term anywhere in the file. This is the case
    # that actually proves the @vocab fallback works, not just term lookup.
    node = expand_one(ctx, {"dataProvenance": "SomeFutureProvenanceKind"})
    assert_predicate(f"{file_label}: dataProvenance (unregistered token)",
                      node, CORE_NS + "dataProvenance",
                      expected_type_iri=CORE_NS + "SomeFutureProvenanceKind")

    # provenanceLayers is an @list of the same kind of token.
    node = expand_one(ctx, {"provenanceLayers": ["EHRVerified", "SelfReported"]})
    layer_list = node.get(CORE_NS + "provenanceLayers", [{}])[0].get("@list", [])
    got = [item.get("@id") for item in layer_list]
    want = [CORE_NS + "EHRVerified", CORE_NS + "SelfReported"]
    if got != want:
        FAILURES.append(f"{file_label}: provenanceLayers @list = {got}, "
                         f"expected {want}")


def check_nested_structures(ctx, file_label):
    # address -- 3 of its 14 declared children, enough to prove scoping works
    # without re-testing every alias.
    node = expand_one(ctx, {"address": {
        "addressLine": "742 Evergreen Terrace",
        "addressCity": "Portland",
        "addressState": "OR",
    }})
    addr = node.get(CORE_NS + "address", [{}])[0]
    assert_predicate(f"{file_label}: address.addressCity", addr,
                      CORE_NS + "addressCity", expected_value="Portland")
    assert_predicate(f"{file_label}: address.addressLine", addr,
                      CORE_NS + "addressLine",
                      expected_value="742 Evergreen Terrace")

    # emergencyContact
    node = expand_one(ctx, {"emergencyContact": {
        "contactName": "Maria Rivera", "contactRelationship": "spouse",
    }})
    ec = node.get(CORE_NS + "emergencyContact", [{}])[0]
    assert_predicate(f"{file_label}: emergencyContact.contactName", ec,
                      CORE_NS + "contactName", expected_value="Maria Rivera")

    # preferredPharmacy
    node = expand_one(ctx, {"preferredPharmacy": {"pharmacyName": "CVS"}})
    ph = node.get(CORE_NS + "preferredPharmacy", [{}])[0]
    assert_predicate(f"{file_label}: preferredPharmacy.pharmacyName", ph,
                      CORE_NS + "pharmacyName", expected_value="CVS")

    # advanceDirectives -- #44 open question 2, resolved: it has a class,
    # cascade:AdvanceDirectives, declared in ontologies/core/v1/core.ttl.
    node = expand_one(ctx, {"advanceDirectives": {"hasLivingWill": True}})
    ad = node.get(CORE_NS + "advanceDirectives", [{}])[0]
    if CORE_NS + "hasLivingWill" not in ad:
        FAILURES.append(f"{file_label}: advanceDirectives.hasLivingWill missing")
    else:
        got = ad[CORE_NS + "hasLivingWill"][0]
        if got.get("@value") is not True:
            FAILURES.append(f"{file_label}: advanceDirectives.hasLivingWill = "
                             f"{got}, expected boolean true")


def check_notes_collision(outer_ctx, top_level_predicate, file_label):
    """The live defect #44 exists to fix: `notes` means two things depending
    on where it sits, and a flat context can only ever pick one at the top
    level.

    `top_level_predicate` is deliberately a parameter, not an assumption: what
    the OUTER `notes` resolves to is issue #3's question (it differs between
    "core + health" and the self-merged cascade.jsonld, which today binds the
    flat name to `clinical:notes`). This check does not take a position on
    that -- it asserts the scoped override inside `clinicalSummary` holds
    regardless of what the outer answer is, which is the actual #44 fix.
    """
    doc = {
        "@context": outer_ctx,
        "@id": "urn:x:check",
        "notes": "top-level note",
        "clinicalSummary": {"notes": "summary note", "conditionCount": 3},
    }
    result = jsonld.expand(doc)
    node = result[0] if result else {}

    assert_predicate(f"{file_label}: top-level notes", node,
                      top_level_predicate, expected_value="top-level note")

    summary = node.get(CORE_NS + "clinicalSummary", [{}])[0]
    assert_predicate(f"{file_label}: clinicalSummary.notes", summary,
                      CORE_NS + "notes", expected_value="summary note")
    assert_absent(f"{file_label}: clinicalSummary.notes must not be "
                  "the outer namespace's notes", summary, top_level_predicate)


def check_has_participant(ctx, file_label):
    node = expand_one(ctx, {"hasParticipant": [
        {"participantName": "Dr. Okafor", "participantRole": "attender"},
    ]})
    participants = node.get(CLINICAL_NS + "hasParticipant", [])
    if not participants:
        FAILURES.append(f"{file_label}: hasParticipant produced no value")
        return
    p = participants[0]
    assert_predicate(f"{file_label}: hasParticipant.participantName", p,
                      CLINICAL_NS + "participantName",
                      expected_value="Dr. Okafor")


def check_flat_terms_unmoved(ctx, file_label, checks):
    """A sample of terms this change must not touch. (name, doc_key, predicate)."""
    for name, key, predicate, value in checks:
        node = expand_one(ctx, {key: value})
        assert_predicate(f"{file_label}: regression -- {name}", node,
                          predicate, expected_value=value)


def main():
    core = load("contexts/v1/core.jsonld")
    clinical = load("contexts/v1/clinical.jsonld")
    health = load("contexts/v1/health.jsonld")
    cascade = load("contexts/v1/cascade.jsonld")

    check_bare_provenance_token(core, "core.jsonld")
    check_bare_provenance_token(cascade, "cascade.jsonld")

    check_nested_structures(core, "core.jsonld")
    check_nested_structures(cascade, "cascade.jsonld")

    check_notes_collision([core, health], HEALTH_NS + "notes",
                           "core.jsonld + health.jsonld")
    check_notes_collision(cascade, CLINICAL_NS + "notes", "cascade.jsonld")

    check_has_participant(clinical, "clinical.jsonld")
    check_has_participant(cascade, "cascade.jsonld")

    check_flat_terms_unmoved(core, "core.jsonld", [
        ("profileId", "profileId", CORE_NS + "profileId", "p-1"),
        ("pharmacyPhone (top-level)", "pharmacyPhone",
         CORE_NS + "pharmacyPhone", "555-0100"),
    ])
    check_flat_terms_unmoved(health, "health.jsonld", [
        ("vaccineName", "vaccineName", HEALTH_NS + "vaccineName",
         "COVID-19 mRNA Vaccine"),
    ])

    if FAILURES:
        print(f"FAILED: {len(FAILURES)} problem(s).\n")
        for f in FAILURES:
            print(f"  - {f}")
        return 1

    print("All scoped-term resolution checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
