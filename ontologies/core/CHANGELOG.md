# Core Vocabulary Changelog

## v3.11 - 2026-09-01

The value set that D-CONSENT-1 ratified as OPEN shipped closed, at `sh:Violation`.

- Added `cascade:SubstanceUseConsent` and `cascade:MentalHealthConsent`, each an
  `owl:NamedIndividual` also typed `cascade:ConsentScope`, matching
  `cascade:SocialHistoryConsent`. SHACL: `cascade:ConsentScopeShape` in
  `core.shapes.ttl` v1.9. Closes jayostis/spec#38.
- **What was wrong.**
  `decisions/2026-09-01-consent-architecture.md` (D-CONSENT-1) ratified the scope
  value set as `social-history`, `substance-use`, `mental-health` and ratified the
  enumeration OPEN — *"`sh:in` at `sh:Warning` at most, never `sh:Violation`"*,
  because *"a closed list missing a member rejects conformant data"*. v3.10
  published one member at `sh:Violation`, so a record tagged substance-use or
  mental-health — data the decision calls conformant — was **rejected**, with an
  `sh:InConstraintComponent` violation. The decision named that outcome in
  advance.
- **Severity is two constraints, not one.** The ratification demotes the *value
  set*. It says nothing about the structural checks sharing the block, and
  demoting those too would have turned "two consent scopes on one record" and "a
  literal instead of an IRI" from rejections into warnings, which nothing asked
  for. So `cascade:ConsentScopeShape`'s single property block **splits**:
  `sh:nodeKind`, `sh:minCount` and `sh:maxCount` stay `sh:Violation` in a block
  carrying no `sh:in`; a second block carries `sh:in` alone at `sh:Warning`.
  Declaring `sh:severity` beside a combined block is not an alternative —
  severity belongs to a shape, not to one of its constraints.
- **Rule S5 does not bite.** Nothing reaches `cascade:ConsentScopeShape` by
  `sh:node` or `sh:qualifiedValueShape` — it is targeted only by
  `sh:targetSubjectsOf` — so the Warning is delivered as a Warning and
  `scripts/known-severity-escalations.json` gains nothing. That precondition is
  now asserted rather than assumed, by a new check,
  `scripts/check-consent-scope-enumeration.py`, which also asserts the
  membership, the severity and the block split, and carries its own negative
  controls (`scripts/test-check-consent-scope-enumeration.sh`).
- **The list is `9ea7c78`'s, not a fresh choice.** D-CONSENT-1 also corrects the
  history that jayostis/spec#20 and #30 reconstructed backwards: the record class
  and its three fields were authored first in `sdk-typescript` (`9ea7c78`,
  2026-03-28), and this repository's `e059b3b` is a late partial copy, not the
  origin.
- **Prose that enumerated the members is deleted rather than extended.**
  `cascade:consentScope`'s `rdfs:comment` said *"Value is one of the
  `cascade:ConsentScope` named individuals: `cascade:SocialHistoryConsent`"*; with
  three members that is false, not merely stale, and a prose copy is a third
  place to keep in sync and the only one nothing checks. `rdfs:range` names the
  class and `sh:in` holds the members. `cascade:ConsentScope`'s own comment drops
  "Closed" for the same reason, and the shape's comment drops "in core v3.10" —
  the open-world statement is true of every release.
- **Strictly more permissive; nothing that conformed stops conforming.** Two
  values that were rejected now conform, and an IRI outside the list moves from
  Violation to Warning. No presence constraint is added anywhere, on any class,
  at any severity: the core v3.5 ratchet is untouched and step 2 still waits on a
  reference producer emitting the predicate. `ontologies/clinical/` is not
  touched.
- **Deliberately not here, now on ratified authority rather than on an open
  question:** `cascade:ConsentRecord` and `consentGrantedAt` /
  `consentRevokedAt`. D-CONSENT-1 settles their shape — FHIR Consent alignment,
  in `consents/` — and then says building *"waits for the first consumer. Nothing
  should invent an interim representation."*
- JSON-LD: both new individuals added to `contexts/v1/core.jsonld` beside
  `SocialHistoryConsent`.

## v3.10 - 2026-08-31

A value that had been declared for six months with no property to carry it.

- Added `cascade:ConsentScope` (`owl:Class`, a closed code list),
  `cascade:consentScope` (`owl:ObjectProperty`, `rdfs:range cascade:ConsentScope`),
  and retyped `cascade:SocialHistoryConsent` as
  `owl:NamedIndividual, cascade:ConsentScope`. SHACL: `cascade:ConsentScopeShape`
  in `core.shapes.ttl` v1.8.
- **The predicate appeared exactly once in this repository, inside another
  property's `rdfs:comment`.** `cascade:proxyScope` says its authority scope is
  *"composable with `cascade:consentScope` (data-sensitivity), which it does not
  replace"* — treating it as a live sibling a reader already has. Searching every
  `.ttl` for the term returned that one line: no `owl:DatatypeProperty`, no
  `owl:ObjectProperty`, no domain, no range, and no `sh:path` in any of the six
  stable shapes files.
- **What made it more than a stale comment is that the value was already here.**
  `cascade:SocialHistoryConsent` has been declared since v3.0 as *"consent scope
  for social history data"*, with a label, a comment naming 42 CFR Part 2, and an
  entry in `contexts/v1/core.jsonld` — a value of a consent-scope property with
  no property it could be the object of. `clinical.ttl` states the obligation
  outright on `clinical:SocialHistoryRecord`: the class *"requires separate
  consent scope (`cascade:SocialHistoryConsent`)"*. The requirement was stated in
  one file and unmeetable in every other. Downstream, `sdk-typescript` names
  `cascade:consentScope` as a predicate in its `TYPE_MAPPING` and silently drops
  the field on serialization, because the predicate is unregistered; its consent
  module is pure in-memory filtering that writes no RDF, which is not a defect
  there — there was no predicate for it to write. Consent scope was enforced by
  application code and left no trace in the graph.
- **`owl:ObjectProperty`, decided on this repository's evidence rather than on
  taste.** The value is already declared as a *resource*, so a datatype property
  would leave it declared, labelled and pointed at by nothing — the exact
  condition being fixed. And thirteen of the fourteen named individuals in
  `core.ttl` already declare their value-class (`cascade:Canonical` is a
  `cascade:ReconciliationStatus`, `cascade:InitialGeneration` is a
  `cascade:GenerationTrigger`); `cascade:SocialHistoryConsent` was the only
  orphan. The section header has read "Consent Scopes", plural, since v3.0: the
  code list was intended from the start and only the class was never written.
  `cascade:proxyScope`'s own prose enumeration (`'full'`, `'read-only'`,
  `'investigation-only'`, in a comment) is the anti-pattern here rather than the
  precedent — an enumeration nothing can check is one a document can contradict.
  That property is left alone; it is a real finding and a separate one.
- **`sh:in`, not `sh:class`, and the distinction is not stylistic.** SHACL
  resolves class membership over the DATA graph. A pod record carries
  `<record> cascade:consentScope cascade:SocialHistoryConsent` and no `rdf:type`
  triple for that object — the type assertion lives here, in the ontology. Nor is
  it rescued by a validator that merges the ontology: `conformance`'s runner
  builds its ontology graph from `rdfs:subClassOf` triples only. `sh:class` would
  have fired on every correctly-authored record, at `sh:Violation`. This
  repository has paid for that once: clinical shapes v1.11 *removed* the
  `sh:class` constraints from `HasEncounterEdgeShape` and
  `LinkedConditionEdgeShape` for the same reason. `sh:in` compares IRIs and is
  entailment-free, which is how all seventeen `cascade:dataProvenance`
  constraints check `cascade:EHRVerified`. It follows that `cascade:ConsentScope`
  does no validation work: it earns its place on the 13-of-14 house-pattern
  argument, and `sh:in` is what a validator actually reads.
- **No PROV superclass on the code list**, for the reason v3.9 removed
  `cascade:DataProvenance`'s. A code list is not record data; asserting otherwise
  enters it into `scripts/check-class-coverage.py`'s population and creates an
  obligation to shape something with nothing to constrain.
  `known-unshaped-classes.json` is unchanged and the check still reports 103
  classes examined, 69 shaped, 34 baselined.
- **No `rdfs:domain` on the property; the range is kept.** Both axioms entail
  rather than constrain, so the question is which entailment is wanted. A domain
  axiom would silently type every subject carrying the predicate, and
  `clinical:SocialHistoryRecord` is not the only class that may want a scope —
  `health:SocialHistoryRecord` and any future sensitive class may too.
- **This release constrains the VALUE and never the PRESENCE.** The shape is
  `sh:targetSubjectsOf`, so a record carrying no consent scope is not evaluated
  and reports nothing. Putting `sh:minCount 1` on
  `clinical:SocialHistoryRecordShape` — which the prose obligation invites — is
  three ratchet steps at once, and the ratchet is written down in the v3.5
  changelog and on `cascade:SourceIdentityShape`. Step 2 is that `sh:minCount 1`
  at `sh:Warning`, once the reference producers emit a scope; step 3 raises it to
  `sh:Violation` after a release in which the Warning is observably absent from
  conforming output. Each is its own vocabulary version and neither is this one,
  so no follow-on issue is filed yet: step 2's precondition does not hold, and a
  dispatchable issue that cannot be started is noise.
- **Compatibility: purely additive, and nothing changes verdict.**
  `ontologies/clinical/` is untouched and `clinical` in `VOCAB_VERSIONS` is
  unchanged, because with the constraint in `core.shapes.ttl` there is nothing
  for a clinical bump to describe. `conformance`'s
  `fixtures/clinical/social-history-smoking.ttl` carries no consent scope, is
  never evaluated by the new shape, and keeps passing untouched.
- **Deliberately not here: a `cascade:ConsentRecord` class**, and the
  `consentGrantedAt` / `consentRevokedAt` properties `sdk-typescript` models. A
  scope value cannot carry them — an individual is a singleton, so it has nowhere
  to put per-instance grant and revocation timestamps. Whether an audit trail of
  when consent was granted and withdrawn is *required* is a 42 CFR Part 2
  question about required fields rather than an RDF modelling one, and
  `pod-structure.md` already reserves `consents/` for ODRL policies and
  `provenance/` for the audit trail, so a consent record class may want a
  different home entirely. Tracked in jayostis/spec#20. Adding the scope property
  first forecloses none of it: a consent record class would carry
  `cascade:consentScope` too.
- JSON-LD: `consentScope` added to `contexts/v1/core.jsonld` with
  `"@type": "@id"`, because the value is an IRI and a context that omits it makes
  the JSON round trip lossy.

*Note on this file: v3.8 and v3.9 have no entry here. Both are recorded in
`core.ttl`'s own changelog block and in the root `CHANGELOG.md`; backfilling them
is not this release's change.*

## v3.7 - 2026-08-27

A Pod gets somewhere to keep the documents its records point at.

- Added `cascade:Attachment` (`owl:Class`, `rdfs:subClassOf prov:Entity`) and
  seven properties: `cascade:hasAttachment` (`owl:ObjectProperty`, range
  `cascade:Attachment`, domain deliberately absent), `cascade:attachmentPath`,
  `cascade:attachmentMediaType`, `cascade:contentHash`,
  `cascade:hashAlgorithm`, `cascade:byteSize`, `cascade:attachmentTitle`. The
  class mirrors the FHIR R4 `Attachment` datatype and every property cites the
  element it mirrors by canonical URL.
- **The bytes are a file, not a literal.** FHIR permits either, via
  `Attachment.data` (inline base64) or `Attachment.url`. A Pod is not a message:
  its Turtle files are parse-critical, read in full by every consumer to answer
  any question, so an unbounded base64 literal is paid for by readers that will
  never open the attachment. The Turtle carries a small metadata node; the bytes
  live under `attachments/{algorithm}/{digest}`, normative in `pod-structure.md`
  section 4.3. The retained `sources/` directory already establishes that a Pod
  can hold non-Turtle content.
- **The file name is the digest.** Content addressing here is not a storage
  optimisation, it is what makes the metadata checkable: a consumer hashes what
  it read and compares it with where it read it from, so nothing has to be
  trusted to keep name and content in agreement. Cross-source deduplication and
  idempotent re-import follow from that with no mechanism behind them. The name
  carries the digest and nothing else — an extension or a media type in the name
  would be a second, unverified claim about the same bytes.
- **The hash algorithm is named, and is not FHIR's.** `Attachment.hash` fixes
  SHA-1 and base64 in the specification and neither is followed. SHA-1 is
  collision-broken, and a collision in a content-addressed store is a mechanism
  for one document to silently replace another. `cascade:hashAlgorithm` carries
  an explicit [RFC 6920](https://www.rfc-editor.org/rfc/rfc6920) registry token,
  and `sha-256` is required of new implementations. The digest is lowercase hex
  rather than base64 because it is also a filename: base64's alphabet contains
  `/` and is case-sensitive.
- **Implementation-defined this release, deliberately:** encryption at rest for
  attachment files, and how the directory participates in Pod sync. Both are
  real and both are deferred rather than forgotten. An implementation may
  encrypt these files by whatever means it already encrypts a Pod; this
  vocabulary states nothing about it, so nothing here is revised when a ratified
  answer arrives.
- SHACL (core.shapes.ttl v1.7): `cascade:AttachmentShape` requires path, digest
  and algorithm at `sh:Violation` — the three facts without which the node
  cannot do its job, and the third is what makes the second checkable rather
  than decorative. The path pattern is stated positively, as `/`-separated
  segments beginning with an alphanumeric, which excludes absolute paths, URLs
  and `..` segments by construction; it is not written as an exclusion because
  SHACL evaluates `sh:pattern` with XPath `fn:matches`, whose XSD 1.1 regular
  expressions have no lookahead. `cascade:AttachmentMediaTypeShape` warns on a
  missing media type; `cascade:HasAttachmentEdgeShape` is open-world
  (`sh:targetSubjectsOf`, `sh:Warning`, no `minCount`, no `sh:class`).
- Compatibility: purely additive. Both node shapes evaluate only
  `cascade:Attachment` nodes, a class no pod written before v3.7 contains, so
  every existing pod validates exactly as it did. Nothing removed, renamed or
  deprecated.
- JSON-LD: eight terms added to `contexts/v1/core.jsonld` and
  `contexts/v1/cascade.jsonld`.

## v3.6 - 2026-08-14

Data absence gets a ratified reason, and a content-derived identifier gets a
canonical form for the fields that became repeatable.

- Added `cascade:dataAbsentReason` (`owl:DatatypeProperty`, domain `owl:Thing`,
  range `xsd:string`): why a record's primary VALUE is absent. Semantics are
  exactly FHIR R4 `Observation.dataAbsentReason`, bound to the 15 codes of
  `http://terminology.hl7.org/CodeSystem/data-absent-reason`. The
  nullFlavor-to-data-absent-reason mapping a C-CDA importer must implement is
  stated on the property, so `UNK`, `NAV`, `NASK` and `ASKU` stop arriving as
  one indistinguishable blank. Binding to data-absent-reason rather than to
  `v3-NullFlavor` is deliberate: this vocabulary already cites it, its codes are
  all selectable where `v3-NullFlavor` marks `NI`/`UNK`/`OTH`/`INV` abstract, and
  FHIR is what both converter paths read.
- Stated the CANONICAL FORM of a multi-valued identity input on
  `cascade:cascadeUri`. No term is added by it: the statement constrains
  implementations, not data. Dedupe, sort by Unicode code point, join with a
  fixed separator (U+002C recommended and required of new implementations), and
  a one-element sequence canonicalizes to the bare scalar. Three invariants are
  normative independently of the separator — order independence, scalar
  agreement, duplicate independence — which is what lets an implementation
  already shipping a different separator comply without re-minting. Scope is
  restricted to inputs that are SETS and must never be widened to an input whose
  source order carries meaning.
- SHACL: `cascade:DataAbsentReasonShape` (core.shapes.ttl v1.6), an open-world
  `sh:targetSubjectsOf` shape. It constrains the VALUE wherever the property
  appears and never requires its presence, so every pod written before v3.6
  validates unchanged. Raw NullFlavor codes are deliberately not accepted: an
  importer maps them on the way in, and accepting both spellings would give
  every absence two encodings.
- JSON-LD: `dataAbsentReason` added to `contexts/v1/core.jsonld` and
  `contexts/v1/cascade.jsonld`.
- No class or property removed, renamed or deprecated.
- Downstream sync (cascadeprotocol.org, conformance, cascade-cli,
  sdk-typescript) in the same train; sdk-python and cascade-agent pending per
  the Vocabulary Change Checklist.

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
