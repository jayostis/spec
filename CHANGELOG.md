# spec/CHANGELOG.md

Top-level changelog for the Cascade Protocol vocabulary specifications. Per-vocab changelogs live in `ontologies/<vocab>/CHANGELOG.md`. This file summarizes cross-vocab milestones.

Format: each entry is one milestone, dated, with a short prose summary and pointers to the per-vocab changelogs that go with it.

---

## 2026-08-14: Four rulings — check the unchecked, keep what was dropped, canonicalize identity inputs (core v3.6, health v2.7, clinical v1.15)

Four independent findings, authored together because three of them touch the same two property shapes and the fourth is what makes those shapes reachable by real converted data. All of it is additive and strictly widening: every graph that validated before validates now, at the same severity, with one deliberate new finding at `sh:Warning` only.

**A vital sign's interpretation was unchecked, and is now checked at Warning.** The v2.6/v1.14 alignment put the 60-value HL7 ObservationInterpretation `sh:in` on the LAB shapes and left `clinical:VitalSignShape` with `sh:datatype` and `sh:maxCount` and no value set, so the identical predicate was validated on a lab result and not on a vital sign. That gap was recorded as intentional because emitted vital data uses `elevated`, which is in neither ratified set, and a Violation would have rejected records that already exist. That reasoning justifies not making it a Violation; it never justified leaving the property unchecked. The binding is applied at `sh:Warning`, which is the ratchet [core v3.5](#2026-08-09-a-records-source-identity-is-declared-canonical-and-never-the-transport-core-v35) wrote down for exactly this case: a value existing data carries is reported, not rejected, and the severity is raised to `sh:Violation` in a later version only after a release in which the warning is observably absent from conforming output. `health:` gains no matching constraint, and that is not an oversight: `health:interpretation`'s domain is `health:LabResultRecord`, and `health:DailyVitalReading`, the only vital class the health vocabulary defines, carries no interpretation predicate at all, so a shape there would constrain a triple no conforming record can write.

**An identifier hashed over an unordered field is not an identifier.** health v2.6 and clinical v1.14 made four code fields 0..\* to match [`CodeableConcept.coding`](https://hl7.org/fhir/R4/datatypes.html#CodeableConcept). An implementation that derives a record's identity from its content then hashes a field that may hold several values, and without a canonical form two exports of the same record that list the same codings in a different order mint two different identifiers and the record silently splits in two. The canonical form is now stated normatively on `cascade:cascadeUri` in `core.ttl`: discard empty members, deduplicate, sort by Unicode code point, join with a fixed separator (U+002C recommended, and required of new implementations). Three invariants are normative independently of the separator, and they are what the conformance vectors check: shuffling members must not change the identifier, a one-value field must mint the same identifier whether spelled as a scalar or a one-element sequence, and repeating a member must not change the identifier. Scalar agreement is what keeps every identifier written before those fields became repeatable exactly where it is.

The scope limit is as load-bearing as the rule. It governs identity inputs whose source element is a SET. It must never be applied to an input whose source order carries meaning — FHIR `name[0]` is the primary name, and a component or note list is a sequence — because sorting there merges records the source deliberately distinguished. An implementation that already ships a different fixed separator keeps it; changing a separator re-mints every identifier the site ever produced, which is precisely the harm the rule exists to prevent.

**Four ways of saying "missing" stopped collapsing into one blank.** A C-CDA document distinguishes `nullFlavor="UNK"` (a value applies, nobody knows it), `NAV` (we will know later), `NASK` (nobody asked) and `ASKU` (we asked, the patient did not know). An importer that drops all four writes one indistinguishable blank, and a reader can no longer tell a test that was never ordered from one whose result is pending. Two ratified code systems already draw the distinction, so none of this is invented: [HL7 v3 NullFlavor](http://terminology.hl7.org/CodeSystem/v3-NullFlavor) (OID 2.16.840.1.113883.5.1008) is what C-CDA writes, and [FHIR data-absent-reason](http://terminology.hl7.org/CodeSystem/data-absent-reason) is the harmonized flat set FHIR R4 binds `Observation.dataAbsentReason` to. Cascade binds to data-absent-reason: it is already the code system this vocabulary cites, its 15 codes are all selectable where v3-NullFlavor marks UNK, NI, OTH and INV abstract, and FHIR is the transport both converter paths read. New `cascade:dataAbsentReason` carries why a record's primary VALUE is absent, with FHIR's exact semantics and the full nullFlavor mapping table stated on the property. Separately, both interpretation value sets gain the fourteen data-absent-reason codes they did not carry, because putting a data-absent-reason coding into the CodeableConcept that is missing is FHIR's own idiom for an element absent for a stated reason, and accepting only `unknown` made every reason the same reason.

**A source code that fits no value set is kept rather than dropped.** New `health:interpretationSourceCode` and `clinical:interpretationSourceCode` carry the source's verbatim interpretation code, written only when that code is a member of neither bound value set. A laboratory's local abnormality flag is the ordinary case. The alternative considered and rejected was accepting the loss with a warning: a closed value set plus a lossy importer means such a flag is either dropped on the floor or written into a field that then fails validation, and in both cases the Pod can no longer answer what the source actually said. The property is deliberately unconstrained — no value set, no pattern, no case folding — because constraining a verbatim carbon copy recreates the loss it exists to prevent. The pair is what makes the vital-sign migration lossless: `interpretation "H"` states the ratified reading and `interpretationSourceCode "elevated"` keeps what the source wrote.

**A procedure was failing for missing a name it was carrying.** A C-CDA import path writes the procedure name to `health:procedureName`, a predicate the health vocabulary does not define, on records it types `clinical:Procedure`. So every converted procedure failed `clinical:ProcedureShape`'s name requirement as though it had no name, and carried its name on a predicate no shape targets, so the name itself was validated by nothing. Measured 2 of 2, 7 of 7 and 1 of 1 across three public sample documents. This is resolved in favour of `clinical:procedureName` rather than by blessing the health: spelling: there is no health-namespace procedure vocabulary at all, so ratifying the emission would mint an undefined-term family of the kind health v2.5 spent a release eliminating; the record is typed `clinical:Procedure`, so a health: name on it is a namespace mismatch inside one record rather than a coherent alternative serialization; and this repository's one dual-spelling precedent, `health:DailyVitalReadingShape`'s `sh:or` over `cascade:date` and `health:date`, exists because both serializations are live and defined, which is not the case here.

`clinical:ProcedureShape`'s name requirement therefore becomes an `sh:or` over both spellings, so a Pod already holding the health: triples stops failing without any data being rewritten, and a new warning-severity `clinical:ProcedureNameSpellingShape` fires wherever the deprecated spelling appears. This is a MIGRATION WINDOW and not a ratified dual: producers write `clinical:procedureName` only, and both the `sh:or` alternative and the warning shape are removed together in a later clinical version once the warning is observably absent from conforming output. A consumer querying `health:procedureName` must add `clinical:procedureName` to its query now.

Tags (applied after merge): `vocab/core-v3.6`, `vocab/health-v2.7`, `vocab/clinical-v1.15`. Per-vocab detail is in `ontologies/core/CHANGELOG.md` and in the inline changelogs of each `.ttl` and `.shapes.ttl`.

---

## 2026-08-09: A record's source identity is declared, canonical, and never the transport (core v3.5)

A Cascade record has always carried two source-shaped properties and needed three. `clinical:sourceEHR` is a display LABEL, worded the way the source document worded it. `cascade:sourceSystem` is the INGESTION batch, which records how and when data entered the Pod. Neither is an origin, and using either as one produces a measurable failure in a different direction.

Keying "are these two records from the same source?" on the ingestion batch answers yes for every pair on a Pod imported under one label, so nothing is ever compared and every duplicate survives; on one real corpus 148 cross-source duplicates were invisible for exactly this reason. Keying on the display label fails the other way: a FHIR export identifies its origin by the registrable domain of its endpoint, and a C-CDA document of the SAME system identifies it by the custodian organization name, so one health system occupies two rows of any source view purely because of which transport the patient happened to download.

**`cascade:sourceIdentity` is the ORIGIN axis.** New in core v3.5, range `xsd:string`, domain `owl:Thing`. Its value is a canonical token that is the same whatever transport carried the record, and it is scheme-prefixed so a consumer can always see how much the producer actually knew: `org:{slug}` when an organization was derivable, `ns:{namespace}` when only an identifier assigning authority was (the FHIR server base URL, or the C-CDA `<id>` root OID), and `transport:{label}` as an honestly-labelled last resort that is explicitly NOT an origin claim. The slug normalization that both transports must implement identically is stated in full on the property in `core.ttl`: reduce an organization name or a registrable domain to its leading distinctive token, dropping generic institution, specialty, legal-form and stopword tokens, so `Meridian Health System` and `meridianhealth.example` both give `org:meridian`, and `Providence Health and Services Washington and Montana` and `providence.org` both give `org:providence`.

**The normalization is deliberately biased toward collapsing.** The two failure directions are not symmetric. Collapsing two different organizations onto one identity suppresses comparisons between their records, so duplicates remain in the Pod, visible and recoverable. Splitting one organization across two identities lets records that organization deliberately kept apart be compared and merged, which destroys content. So regional and specialty qualifiers are dropped rather than being allowed to split a system, and the rule takes the leading distinctive token rather than all of them.

**The other two axes are unchanged, and now say what they are not.** `clinical:sourceEHR` keeps its meaning exactly: a display label, and an application aliases it to the origin rather than reading it as one. `cascade:sourceSystem`'s comment now states that it records how and when data arrived, never where it came from, and must not be used as a reconciliation key. No property was added to, removed from or renamed in any other vocabulary, and no emitted value changes meaning.

**Compatibility: absence is not a finding.** `cascade:SourceIdentityShape` uses `sh:targetSubjectsOf`, so it evaluates only records that already carry the property and reports nothing on a pod written before v3.5. Requiring presence at Warning severity the moment the property is defined would turn every existing pod amber for something no producer had yet had the chance to write, and a warning that fires on correct historical data is one readers learn to skip. The ratchet is written down rather than left to judgement: presence becomes a Warning on the `health:` and `clinical:` record shapes once the reference producers emit it, and a Violation only after a release in which that Warning is observably absent from conforming output. Each step is its own vocabulary version.

Tag (applied after merge): `vocab/core-v3.5`. Per-vocab detail is in `ontologies/core/CHANGELOG.md` and in the inline changelog of `core.ttl` and `core.shapes.ttl`.

---

## 2026-08-08: Align lab, code and date constraints to ratified standards (health v2.6, clinical v1.14, coverage v1.4, checkup v3.3)

Real-world Epic FHIR exports, and C-CDA documents through the same pipeline, were failing `cascade validate` on records that are correct at source. Every failure traced to a Cascade constraint that was narrower than the standard it claimed to describe. This release replaces invented value sets with ratified ones and invented cardinalities with the source resource definitions, and shapes a class that had no shape. Shapes and JSON-LD contexts only: no class or property is added, removed, renamed or deprecated, and apart from the new Encounter shape the change is strictly widening.

**Interpretation is now HL7, not Cascade.** `health:interpretation` and `clinical:interpretation` were constrained to five words this project made up (normal, high, low, abnormal, critical). Both are now bound to the 49 selectable codes of [`http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation`](http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation) version 3.0.0, the code system FHIR R4 binds `Observation.interpretation` to. The eight abstract concepts are excluded because they are hierarchy nodes rather than values; the ten codes the code system marks deprecated are included, because a deprecated code is still a defined code and historical results carry them. A laboratory reporting a susceptibility (S/I/R), detection (POS/NEG/DET/ND/IND), reactivity (RR/WR/NR) or change (B/D/U/W) result was previously rejected for being conformant. The [`data-absent-reason`](http://terminology.hl7.org/CodeSystem/data-absent-reason) code `unknown` is also accepted, for the very common case of a source Observation that carried no interpretation at all. The previous ten words are retained so nothing already written stops validating.

**Multi-valued where FHIR is multi-valued.** `health:labCategory` follows [`Observation.category`](https://hl7.org/fhir/R4/observation-definitions.html#Observation.category), which is 0..\*. `health:testCode`, `health:icd10Code`, `health:snomedCode`, `clinical:snomedCode` and `clinical:icd10Code` follow [`CodeableConcept.coding`](https://hl7.org/fhir/R4/datatypes.html#CodeableConcept), which is 0..\*. Dual-coded problem-list entries and multi-coding lab observations are the normal shape of EHR output, not an anomaly, and `sh:maxCount 1` was rejecting records for preserving what the source sent.

**Codes keep their own format rules.** No `sh:pattern` was added to any code property, and one was corrected. SNOMED CT identifiers are 6-18 digit integers and ICD-10-CM permits a letter in any character position, so a lexical pattern on those buys nothing and costs valid codes. Two patterns that did exist were wrong: `checkup:icd10Code` required digits in the second and third characters, which rejects every code under live categories such as C4A, D3A and M1A (the ICD-10-CM Official Guidelines for Coding and Reporting, Section I.A.2: "Characters for categories, subcategories and codes may be either a letter or a number"); and `clinical:cptCode` required five digits, which is CPT Category I only and rejects Category II (four digits + F), Category III (four digits + T) and Proprietary Laboratory Analyses (four digits + U) codes.

**Insurance follows the FHIR bindings.** `coverage:subscriberRelationship` held five of the seven codes in [`subscriber-relationship`](http://terminology.hl7.org/CodeSystem/subscriber-relationship); `common` and `injured` were simply missing, so a conformant export warned. `coverage:coverageType` enforced a closed four-member enum at Violation severity on an element FHIR R4 binds [extensibly](https://hl7.org/fhir/R4/terminologies.html#extensible), where alternate codes MAY be used; presence stays a Violation, and the value is now checked at Warning against the FHIR value set plus the four retained Cascade values.

**Dates may be date-precision.** FHIR's `dateTime` primitive is explicitly partial-precision, "YYYY, YYYY-MM, YYYY-MM-DD or YYYY-MM-DDThh:mm:ss+zz:zz" ([datatypes](https://build.fhir.org/datatypes.html)), and C-CDA `effectiveTime` commonly carries a calendar day with no time. Date properties whose value is CARRIED OVER from a source document (`clinical:encounterDate`, `clinical:documentDate`, `clinical:onsetDate`, `clinical:procedureDate`, `health:performedDate`, `health:reportedDate`, `health:onsetDate`, `health:administrationDate`) now accept `xsd:date` alongside `xsd:dateTime`, and their JSON-LD terms no longer coerce to `xsd:dateTime`, so a producer states the precision it actually has instead of inventing a midnight. Timestamps Cascade itself generates (`clinical:importedAt`, statistic period bounds, derived episode dates) are unchanged and still require `xsd:dateTime`.

**Encounters are validated at all.** `clinical:Encounter` has been defined since clinical v1.7 and targeted by no shape, so validating an encounter evaluated zero constraints and returned PASS. New `clinical:EncounterShape` and `clinical:EncounterTemporalShape` constrain cardinality, datatype, provenance and the IRI requirement that the `clinical:hasEncounter` edge implies. They deliberately do not constrain what kind of visit an encounter may be: `encounterClass` gets no enum because FHIR binds `Encounter.class` extensibly and servers send either the abbreviation or a display string, and the `encounterStatus` enum is the FHIR R4 `EncounterStatus` value set verbatim at Warning severity. Having a position in time is a Warning, not a Violation, because `Encounter.period` is 0..1.

Tags (applied after merge): `vocab/health-v2.6`, `vocab/clinical-v1.14`, `vocab/coverage-v1.4`, `vocab/checkup-v3.3`. Per-vocab detail is in the inline changelog of each ontology and shapes file.

---

## 2026-08-03: Validation Profile 1.0 (the entailment regime, stated and enforced)

New normative document `validation/index.md`, plus the check that holds this repository to it. No released vocabulary changes; nothing in `VOCAB_VERSIONS` moves.

**The problem.** SHACL is a validation language, not a validation configuration. [SHACL 2.1.3.1](https://www.w3.org/TR/shacl/#targetClass) resolves `sh:targetClass` over SHACL-instances in the DATA graph, and Cascade pod records carry `rdf:type` triples but no schema axioms. A subclass axiom declared in an ontology file therefore confers no shape coverage on the subclass. A validator that merges ontologies into the data graph before validating sees the opposite, and both readings conform to SHACL. The same file could be valid under one implementation and invalid under another with neither doing anything wrong.

**The rule.** Cascade shapes are entailment-independent. Every class a shape means to constrain carries an explicit `sh:targetClass`; constraint inheritance is stated with `sh:node` or a shared target list rather than inferred; `sh:class` value constraints enumerate the acceptable subclasses. A conforming validator MUST reach a correct verdict with no inferencing, MAY perform entailment as an extension, and MUST get the same verdict either way. A verdict difference between an entailing and a non-entailing validator is a defect in the shapes, not a validator configuration question. A conformance suite must be able to reproduce every fixture's expected outcome with no pre-validation merge. The rejected alternative, mandating an ontology merge, is argued in `validation/index.md` §4: it moves correctness into every consumer's configuration and is unenforceable in a library embedded in someone else's application.

`rdfs:subClassOf` is unaffected and still required for modelling. It is what makes `rdfs:domain` / `rdfs:range` true, and it is what the check reads to work out which classes need an explicit target. It is simply not a validation mechanism.

**The enforcement.** `scripts/check-shape-targets.py` evaluates three assertions over every ontology and shapes file here: target closure (T), constraint-set equivalence (I), and value-class closure (C). It reports how many cases each examined and fails if any examined none, because an assertion with nothing to inspect has established nothing. `scripts/test-check-shape-targets.sh` is its regression suite: every assertion is paired with a scratch copy of the repository carrying a deliberately reintroduced violation that the check must catch and name. New CI job `shapes` runs both on every PR touching `ontologies/`. This is the first automated test of this repository's own shapes.

**Found on the first run, and fixed here:** genomics v1-draft.0.5. `genomics:CopyNumberVariantShape` claimed in its comment to inherit `VariantShape` transitively and did not, so copy number variants were never checked for `genomics:dataQualityTier` (the value the `D-QUALITY-TIER` safety constraint on `VariantInterpretation` is evaluated against) or for carrying a stable identifier. Measured across both engines: the same fixture was reported conforming by a non-entailing validator and non-conforming with two Violation results by an entailing one. Fixed with an explicit `sh:node`, after which both engines agree. `HaplotypeShape`'s `hasComponent` `sh:class` was widened to enumerate `CopyNumberVariant`. See `ontologies/genomics/CHANGELOG.md`.

The released vocabularies (`core`, `health`, `clinical`, `coverage`, `checkup`, `pots`) already satisfy all three assertions and are unchanged. No tag; the Validation Profile carries its own version, as `serialization/index.md` does, and `VOCAB_VERSIONS` records vocabulary versions rather than profile versions.

---

## 2026-07-16: clinical v1.9 to v1.10 (graph edge vocabulary)

Gives the importer traversable RDF for the relationships EHR sources carry but the pod has been flattening. Four authored changes to the released `clinical` vocabulary (slice V1 of the graph-retrieval sequenced plan; and 3.11(d); blocks importer slice R3):

- `clinical:hasEncounter` (ObjectProperty, range `clinical:Encounter`): the record-to-encounter edge for grouping clinical events by visit context. FHIR-aligned to the `.encounter` Reference(Encounter) element on Observation, MedicationRequest, Condition, Procedure, DiagnosticReport, DocumentReference. Broad domain, constrained by SHACL rather than a restrictive `rdfs:domain` union.
- `clinical:indicationReference` (ObjectProperty, open range `rdfs:Resource`): the medication-to-condition indication edge, alongside the retained free-text `clinical:indication` / `clinical:reasonForUse` literals. FHIR-aligned to `MedicationRequest.reasonReference` (R4; `reason` CodeableReference in R5). Range left open because FHIR allows Condition or Observation.
- `clinical:linkedCondition` (ObjectProperty, Condition to Condition) plus `owl:deprecated true` on `clinical:linkedConditionIds`. Replaces the space-separated-UUID literal wart with a real traversable edge; the old property is retained (not removed) for backward compatibility with existing Checkup data.
- `clinical:hasLabResult` `rdfs:range` corrected from `clinical:LabResult` to `health:LabResultRecord`, matching the class both importer paths actually type panel members. Non-breaking (no SHACL shape constrained the edge target). Surfaced a related gap: `health:LabResultRecord` is emitted by the importer but has no class definition in the health vocabulary, filed as a follow-up.

Shapes: three open-world `sh:targetSubjectsOf` PropertyShapes (IRI nodeKind, class where the range is committed, `sh:Warning`, no `minCount`), so no pod current or future fails validation on account of these edges. JSON-LD context: the three ObjectProperties as `@type: @id`.

Tag: `vocab/clinical-v1.10` (applied after merge). See the inline changelog in `ontologies/clinical/v1/clinical.ttl`. The `cascade-cli` shape sync ships promptly in its own PR so `cascade validate` knows the terms; the rest of the 7-repo checklist (docs site, conformance, both SDKs, agent) is BATCHED per `PENDING_DOWNSTREAM_SYNC.md` (Pending batch, clinical v1.10).

---

## 2026-07-15 — workbench v1-draft.0.5 (notes / flags / follow-ups as W3C Web Annotations)

Caregiver notes, "needs research" flags, and follow-ups become ONE substrate: `oa:Annotation` over one or more graph nodes, distinguished by `oa:motivatedBy`, with required PROV-O attribution. Maximal Layer-1 reuse: span selectors from `oa:`, due date + status for follow-ups from W3C RDF Calendar (`ical:due` / `ical:status`, follow-ups dual-typed `cal:Vtodo`). Exactly one term minted: `workbench:followUp` (an `oa:Motivation`, `skos:broader oa:questioning`). `workbench:InvestigationNote` removed (draft; unshipped), superseded by the substrate. New Pod container `notes/` documented in `pod-structure.md` §5.2. SHACL Core shapes verified against `cascade validate` with positive + negative fixtures. Unblocks Workbench shell Phase 9 (notes grammar).

Tag: `vocab/workbench-v1-draft.0.5` (applied after merge). See `ontologies/workbench/CHANGELOG.md`. Downstream propagation is BATCHED per `PENDING_DOWNSTREAM_SYNC.md` (row 4) together with the outstanding v1-draft rows.

---

## 2026-07-01 — evidence v1-draft.0.2 (verdict taxonomy v2: the facet model)

The `evidence:` grounding outcome moves from the flat 4-value `evidence:verdict` to orthogonal **facets** on the Assertion: `evidence:direction` / `basis` / `strength` / `settled` / `reason` (object properties over new closed enumerations `DirectionValue` / `BasisValue` / `StrengthValue` / `SettledValue` / `NeedsEvidenceReasonValue`) plus `evidence:confidence` (`xsd:decimal`, [0,1]). The facets are the canonical serialized form. The generalized SHACL-Core grounding invariant: a grounded result (settled Settled, non-None direction, non-None basis) of EITHER basis requires at least one `evidence:hasEvidenceLink`, plus facet-consistency constraints (NeedsEvidence must not carry a grounded direction; a grounded direction requires a real basis). Some individuals are shared across facets (e.g. `Supports`/`Contradicts` are both `StanceValue` and `DirectionValue`; `None` is both `DirectionValue` and `BasisValue`; `NeedsLiterature` doubles as the deprecated `VerdictValue` and a `NeedsEvidenceReasonValue`). `evidence:verdict` and the `VerdictValue` individuals are **deprecated, not removed**, kept one release so draft-period data still validates; both are scheduled for removal at v1.0 graduation (see `PENDING_DOWNSTREAM_SYNC.md`).

Tag: `vocab/evidence-v1-draft.0.2` (applied after merge). See `ontologies/evidence/CHANGELOG.md`. Downstream propagation is BATCHED per `PENDING_DOWNSTREAM_SYNC.md` (row 2), synced 2026-07-15 together with the outstanding v1-draft rows.

---

## 2026-06-28 — workbench v1-draft.0.4 (userSourceLabel filing axis)

Adds the filing / organization axis to `workbench:`: `workbench:userSourceLabel` (`xsd:string`), the user-chosen label for the SOURCE a record is filed under in the Workbench "filing cabinet". It is a filing preference attributed to the user, carried on a `workbench:Annotation` overlay (`annotationProperty` = `"workbench:userSourceLabel"`, `annotationValue` = the chosen label) bearing `cascade:SelfReported` provenance. It MUST NOT overwrite the objective imported origin `clinical:sourceEHR`, which is preserved and displayed alongside; the effective grouping source prefers this label, else falls back to `clinical:sourceEHR` / the import-batch tag. Orthogonal axis with an open domain (mirroring `workbench:verificationStatus` in v1-draft.0.3), so it can file any record. No new SHACL shape: the overlay reuses the already-shaped `workbench:annotationProperty` / `workbench:annotationValue` string predicates.

Tag: `vocab/workbench-v1-draft.0.4` (applied after merge). See `ontologies/workbench/CHANGELOG.md`. Downstream propagation is BATCHED per `PENDING_DOWNSTREAM_SYNC.md` (row 1), synced 2026-07-15 together with the outstanding v1-draft rows.

---

## 2026-05-06 — genomics v1-draft.0.3 (shape relaxations from test-fixture review)

Two SHACL shape relaxations on `genomics/v1-draft`. No vocabulary additions; shapes only.

- `genomics:geneSymbol` on `VariantShape`: Violation → Warning. The required-cardinality `sh:minCount 1` is removed; `sh:maxCount 1` stays. VRS preserve-only imports (D-Q6) and gene-less VCF records legitimately lack gene context.
- `genomics:variantInterpreted` range widened from `genomics:Variant` alone to `{Variant, CopyNumberVariant, Haplotype}` via `sh:or`. Clinical interpretations attach to all three molecular-record types (e.g., the retinoblastoma phenopacket interprets a chr13 CNV).

Tag: `vocab/genomics-v1-draft.0.3` (orchestrator-applied after merge). See `ontologies/genomics/CHANGELOG.md` for the full per-vocab entry, including the list of fixtures that become SHACL-clean post-relaxation and the deferred-to-later candidates.

Source: `cascade-coordination/tie-breaks/2026-05-06-vrs-geneSymbol-shape.md` and the Phenopacket test-fixture agent's report (variantInterpreted CNV violation).

---

## 2026-05-06 — core/v1 3.1 → 3.2 (forward-reference closure)

Small additive bump on `core/v1` to retroactively declare `cascade:appliedTriplesCount`. The Phase 4 advisory applier (cascade-cli TASK-4.5) was already emitting this property on every `cascade:AdvisoryApplicationActivity` record as a documented forward reference; this milestone closes the loop.

- `cascade:appliedTriplesCount` (DatatypeProperty, `xsd:nonNegativeInteger`, domain `cascade:AdvisoryApplicationActivity`). Records the number of triples a single advisory application inserted into the pod — auditable post-hoc verification of CAP profile constraint C5 (≤ 64 inserted triples per match).
- SHACL: Info-severity property shape on `AdvisoryApplicationActivityShape` (recommended, not required — existing activity records without the stamp remain SHACL-clean).
- VOCAB_VERSIONS: `core=3.2`. See `ontologies/core/CHANGELOG.md` for the full per-vocab entry.

Tag: `vocab/core-v3.2` (orchestrator-applied after merge).

---

## 2026-05-05 — Genomics v1-draft.0.2 evolution

Small, additive evolution pass on `genomics/v1-draft` driven by gaps surfaced in the Phase 1 FHIR Genomics IG importer (cascade-cli) and the TASK-1.9 HLA tie-break. Four high-confidence additions; nothing removed or renamed.

- **`genomics:reportedRecord`** (ObjectProperty, no `rdfs:range` — deliberately broad). Generic GeneticTest → record predicate for non-Variant report links (Diplotype, Haplotype, PGx implication, future genomics record types). Resolves the HLA tie-break: `genomics:variantsObserved` has `rdfs:range genomics:Variant` and cannot represent these without a range violation. Importers should still emit the more specific `variantsObserved` for true Variant references.
- **`genomics:refAllele`, `genomics:altAllele`, `genomics:genomicStartEnd`** (DatatypeProperty, `xsd:string`). VCF-style coordinate properties mapping LOINC 69547-8 / 69551-0 / 81254-5. Required for the Phase 3 VCF importer and for FHIR Genomics IG variants that lack HGVS but carry the LOINC components directly.
- **`genomics:somaticStatus`** ObjectProperty + **`genomics:SomaticStatus`** class with three named individuals (`Germline`, `Somatic`, `UnknownSomaticStatus`). Maps LOINC 48002-0 (Genomic source class). Critical for cancer interpretation and inheritance reasoning.
- **`genomics:variantAlleleFrequency`** (DatatypeProperty, `xsd:decimal`, SHACL-bounded 0.0–1.0). Maps LOINC 81258-6. Distinct from the existing `genomics:mosaicismFraction` — VAF is a sequencing-evidence fraction; mosaicism is the clinical conclusion that the variant is present in only a subset of cells. Phase 1 importer was shoehorning VAF into mosaicismFraction; this is the proper home.

SHACL: VariantShape gains optional property shapes for all five new Variant-domain properties (Info severity for the three string coordinates; Violation severity for the closed-enumeration `somaticStatus` and the 0.0–1.0 range on `variantAlleleFrequency`). No NodeShape added for `reportedRecord` — its domain breadth is intentional. All existing fixtures continue to pass.

Per D-PATH this is still a draft; no `VOCAB_VERSIONS` change. Tag: `vocab/genomics-v1-draft.0.2` (orchestrator-applied after merge). See `ontologies/genomics/CHANGELOG.md` for the full per-vocab entry, including the deferred-to-later candidates (CompositeVariant, multi-gene Diplotype, cytogenetic location, SNOMED reaction coding).

---

## 2026-05-05 — Genomics & Advisory v1-draft.0.1 milestone (TASK-0.5)

First draft of the Genomics & Advisory v0.1 implementation workstream lands in `spec/`:

- **`core/v1`** bumped 3.0 → 3.1 (TASK-0.0). Adds two new `prov:Activity` subclasses to support the workstream:
  - `cascade:AdvisoryApplicationActivity` — records application of a Cascade Advisory Patch to a pod, joining the advisory and the matched record via `prov:used`.
  - `cascade:AIGenerationActivity` — sibling of `cascade:AIExtractionActivity` for LLM-generated narrative content (e.g., `checkup:VariantNarrative`). Carries `cascade:promptVersion`, `cascade:generationTemperature`, and a `cascade:trigger` ObjectProperty with three `cascade:GenerationTrigger` named individuals: `InitialGeneration`, `RegenerationAfterReclassification`, `AudienceRetargeting`. A single class with a trigger property was preferred over multiple subclasses (e.g., a separate `AIRegenerationActivity`) — avoids over-modeling.
  - SHACL shapes mirror the structure: `AIGenerationActivityShape` requires `extractionModel` + `trigger`; `AdvisoryApplicationActivityShape` requires `prov:used minCount 2` (advisory IRI + matched-record IRI).
  - See `ontologies/core/CHANGELOG.md` for the full v3.1 entry.

- **`genomics/v1-draft.0.1`** authored (TASK-0.1, TASK-0.2). 220 declared `genomics:` terms across 14 classes, ~30 net-new properties versus the v0.1 design draft.
  - Layer 2 vocabulary at `https://ns.cascadeprotocol.org/genomics/v1#` with `owl:versionInfo "1.0-draft"` per D-PATH. Pre-stable drafts are NOT registered in `VOCAB_VERSIONS` (they land there at v1.0 stable graduation only).
  - Folds in all GAP-ANALYSIS additions (Haplotype, Diplotype, CopyNumberVariant, SubmitterAssertion, GeneticTestOrder, interpretationStatus + 7-value ReviewStatus enum).
  - Folds in the directory-session additions per D-DIRECTORY (SequencingRun, RawFile + 6 properties, sequencing-run metadata, dataProvenance enum).
  - Folds in the data-quality tier model per D-QUALITY-TIER (DataQualityTier class + 4 tier individuals: ClinicalGrade, ResearchGrade, ConsumerGrade, UnknownQuality; `requiresConfirmation` property on `VariantInterpretation`).
  - SHACL shapes (TASK-0.2) enforce: D-Q5 multi-condition cardinality (`condition` 1..1, `variantInterpreted` 1..1, reclassification chain via `prov:wasRevisionOf`); D-QUALITY-TIER safety constraint expressed as `sh:xone` on `VariantInterpretation` — Pathogenic/LikelyPathogenic interpretations MUST either reference a `ClinicalGrade` Variant OR carry `requiresConfirmation true`.
  - 12 `sh:NodeShape` declarations covering every concrete class.
  - See `ontologies/genomics/CHANGELOG.md`.

- **`advisory/v1-draft.0.1`** authored (TASK-0.3, TASK-0.4). 55 declared `advisory:` terms (8 classes, 16 named individuals across 3 enums, 31 properties).
  - Layer 2 vocabulary at `https://ns.cascadeprotocol.org/advisory/v1#` with `owl:versionInfo "1.0-draft"` per D-PATH.
  - Defines the Cascade Advisory Patch (CAP) envelope: `CascadeAdvisoryPatch`, `AutoApplyPolicy`, `AdvisoryClass` (six named individuals: `SafetyCritical`, `VariantReclassification`, `DrugInteraction`, `LabReferenceRangeUpdate`, `SurveillanceGuidelineUpdate`, `CarrierFrequencyUpdate`), `TrustedIssuer` per D-Q3 (per-pod, with `TrustSourceEnum` for provenance: `RecommendedStarterList`, `UserAdded`, `ImportedFromRegistry`, `VerifiedViaDID`).
  - Signing envelope per D-Q4: detached JWS Ed25519 (RFC 7515 compact serialization). Properties for `signature`, `signatureIssuer` (iss), `signatureIssuedAt` (iat), `signatureExpiresAt` (exp), `signatureContentType` (cty, fixed to `application/x-cascade-advisory-patch`).
  - Six tiered cadences: `EveryAppOpen`, `Daily`, `Weekly`, `Monthly`, `Quarterly`, `Annually`.
  - SHACL shapes (TASK-0.4) enforce: required envelope fields (humanSummary, advisoryClass, issuer, issuedAt); closed enumerations on advisoryClass/cadence/trustSource; `appliesTo` cardinality on AutoApplyPolicy; AutoApplyScope structure. Issuer-trust allowlist enforcement is OUT of SHACL scope per D-Q3 (runtime concern, lives in `<pod>/trust/issuers.ttl`).
  - 4 `sh:NodeShape` declarations.
  - See `ontologies/advisory/CHANGELOG.md`.

### Tags landed in this milestone

- `vocab/genomics-v1-draft.0.1` on `spec/main`
- `vocab/advisory-v1-draft.0.1` on `spec/main`
- `gate/0a-passed` on `cascade-coordination/main` (cross-repo gate marker)

### Workstream context

The Genomics & Advisory v0.1 implementation plan lives at `cascadeprotocol.org/drafts/05-04-26 Genomics & Advsiory IMPLEMENTATION-PLAN.md`. Decision tracker rows resolved in this milestone: D-PATH, D-Q3, D-Q4, D-Q5, D-Q6, D-N1, D-N3, D-N4, D-N5, D-N6, D-Q8, D-A, D-B, D-DIRECTORY, D-QUALITY-TIER, D-Q10. Phase -1 readiness prep complete; Gate 0a achieved with this entry.

### What's next (Gate 0b prep)

- TASK-0.6: downstream sync to `cascadeprotocol.org` (HTML docs, schemas.md update, llms-full.txt regeneration).
- TASK-0.7: conformance fixture skeletons in `conformance/fixtures/{genomics,advisory}/`.
- After both: Gate 0b sign-off, which unblocks Phase 1+ importers and SDK propagation.
