# Core Vocabulary Changelog

## v3.5 - 2026-08-09

The ORIGIN axis: a declared source identity that is canonical across transports.

- Added `cascade:sourceIdentity` (`owl:DatatypeProperty`, domain `owl:Thing`,
  range `xsd:string`): the canonical, transport-independent identity of the
  organization a record came from. Scheme-prefixed so a reader can tell how much
  the producer knew: `org:{slug}`, `ns:{namespace}` (FHIR server base URL or
  C-CDA `<id>` root OID), `transport:{label}` as an honestly-labelled last resort
  that is not an origin claim. The slug normalization both transports must
  implement is stated on the property in `core.ttl`.
- Documented the three source axes in `core.ttl` and narrowed
  `cascade:sourceSystem`'s comment to say what it is NOT: it is the INGESTION
  batch, records how and when data arrived rather than where it came from, and
  must not be used as a reconciliation key. `clinical:sourceEHR` remains the
  display LABEL with unchanged semantics.
- SHACL: `cascade:SourceIdentityShape` (core.shapes.ttl v1.5), an open-world
  `sh:targetSubjectsOf` shape. It constrains the VALUE wherever the property
  appears (single, string, one of the three schemes) and never requires its
  presence, so every pod written before v3.5 validates unchanged. Ratchet path
  to Warning and then Violation is written into the v3.5 changelog in
  `core.ttl`.
- JSON-LD: `sourceIdentity` and `sourceSystem` added to `contexts/v1/core.jsonld`
  and `contexts/v1/cascade.jsonld`.
- No class or property removed, renamed or deprecated.
- Downstream sync (cascadeprotocol.org, conformance, cascade-cli) in the same
  train; sdk-typescript, sdk-python and cascade-agent pending per the Vocabulary
  Change Checklist.

## v3.3 - 2026-06-16

Cascade Workbench support: ungrounded-AI provenance + caregiver-proxy.

- Added `cascade:AIAsserted` (`owl:Class`, subClassOf `cascade:ConsumerGenerated`):
  provenance leaf for content surfaced by a general-purpose AI assistant in a
  patient-directed conversation. Safety primitive: marks `evidence:Assertion`
  inputs as ungrounded-by-construction so they are never confused with
  `cascade:AIExtracted` clinical data.
- Added `cascade:ProxyAgent` (`owl:Class`, subClassOf `prov:Agent`) and properties
  `actsForPatient`, `proxyWebID`, `proxyRelationship`, `proxyScope`,
  `proxyGrantedAt`, `proxyRevokedAt`: caregiver-proxy actor (e.g. a parent
  operating a minor child's Pod).
- SHACL: `cascade:ProxyAgentShape` (requires actsForPatient, proxyRelationship,
  proxyGrantedAt).
- Downstream sync (cascade-cli, sdk-typescript, sdk-python, cascade-agent) pending
  per the Vocabulary Change Checklist.

## v3.2 — 2026-05-06

Forward-reference closure for the Phase 4 advisory applier.

- Added `cascade:appliedTriplesCount` (`owl:DatatypeProperty`, range
  `xsd:nonNegativeInteger`, domain `cascade:AdvisoryApplicationActivity`).
  Records the number of triples a single advisory application inserted into
  the pod, enabling post-hoc auditable verification of CAP profile constraint
  C5 (≤ 64 inserted triples per match).
- The Phase 4 applier (cascade-cli `src/lib/advisory/applier.ts`) was already
  emitting this property as a documented forward reference; v3.2 retroactively
  declares it. No applier code change is needed; existing emitted records
  become SHACL-clean (Info-severity property shape encourages but does not
  require the stamp).

## v3.1 — 2026-05-05

Genomics & Advisory provenance (TASK-0.0). Two new `prov:Activity` subclasses
plus a trigger enumeration for AI generation events.

- Added `cascade:AdvisoryApplicationActivity` (`rdfs:subClassOf prov:Activity`).
  Created when a Cascade Advisory Patch is applied to a pod. Joins to
  advisory provenance via `prov:used <advisory-iri>` and
  `prov:used <matched-record-iri>`.
- Added `cascade:AIGenerationActivity` (`rdfs:subClassOf prov:Activity`).
  Sibling of `cascade:AIExtractionActivity` for LLM-generated narrative
  content (e.g., `checkup:VariantNarrative` chunks). Reuses
  `cascade:extractionModel`, `cascade:extractionConfidence`,
  `cascade:sourceNarrativeSection`, and `cascade:requiresUserReview` from
  `AIExtractionActivity`. Adds `cascade:promptVersion` and
  `cascade:generationTemperature`.
- Added `cascade:trigger` (`owl:ObjectProperty`,
  `rdfs:domain cascade:AIGenerationActivity`,
  `rdfs:range cascade:GenerationTrigger`).
- Added `cascade:GenerationTrigger` class with three named individuals:
  `cascade:InitialGeneration`, `cascade:RegenerationAfterReclassification`,
  `cascade:AudienceRetargeting`.
- Added SHACL shapes `cascade:AIGenerationActivityShape` and
  `cascade:AdvisoryApplicationActivityShape`.

Design note: a single `AIGenerationActivity` class with a `trigger` property
was chosen over multiple subclasses (e.g., a separate
`AIRegenerationActivity`). One class is enough.
