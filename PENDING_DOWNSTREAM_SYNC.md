# Pending downstream sync ledger

**Purpose.** A vocabulary change is *authored* in `spec/` continuously, but its
propagation to the six downstream repos (the steps 2–7 of the Vocabulary Change
Checklist in `CONTRIBUTING.md`) is **expensive to do one change at a
time**. This ledger lets us accumulate authored-but-not-yet-propagated changes
and run the full 7-repo sync **in one batch** at a release boundary (e.g. weekly,
or when a draft vocab is promoted out of `v1-draft`).

## Why batching is safe here

1. **Shapes are open-world (not `sh:closed`).** A converter/importer can EMIT a
   new predicate and the Pod still passes `cascade validate` *before* the
   predicate is formally in the embedded shapes. So the DATA can ship as soon as
   `spec/` defines the term; the shape/docs/SDK propagation can lag.
2. **The `v1-draft` namespace is the accumulation buffer.** Draft ontologies
   (e.g. `workbench/v1-draft`) are not listed in `VOCAB_VERSIONS` and do not gate
   downstream releases. Terms accrue in draft; the 7-repo cascade fires only when
   a draft is promoted to a released `vN`.

## The seam (what must sync NOW vs what batches)

| Need | Sync immediately | Batches |
|---|---|---|
| Importer/app emits a new **draft** predicate | `spec/` (author the term) | docs site, conformance, CLI shapes, both SDKs, agent |
| A **released** vocab (`core`/`clinical`/…) gains a property | `spec/` + `cascade-cli` shapes (so `cascade validate` knows it) | docs site, conformance, both SDKs, agent |

Open-world validation means even the released-vocab case usually does not *block*
on the CLI shape sync; do it promptly only so `validate` documents the new term.

## How to run the batch

1. `cd spec && sh scripts/check-downstream-versions.sh` — see drift across repos.
2. For each ledger row below, run the per-repo steps (`CONTRIBUTING.md` cross-repo sequence, steps 2–7).
3. Tag `vocab/{name}-v{X.Y}`, update each repo's `VOCAB_VERSIONS`, clear the row.

---

## Done — batched sync 2026-07-15

The three v1-draft rows below were propagated in one batch (Vocabulary Change
Checklist steps 2–7). One PR per repo; every box is checked with its PR number.
Drafts stay UNROWED in `VOCAB_VERSIONS` per D-PATH (each SDK/repo added a dated
comment only), so the released-vocab drift check still reads UP TO DATE across
all repos. Tags `vocab/workbench-v1-draft.0.5`, `vocab/workbench-v1-draft.0.4`,
and `vocab/evidence-v1-draft.0.2` are applied on merge.

**Per-repo PRs (shared across the three rows):**

| Repo | PR | What synced |
|---|---|---|
| cascade-cli | the-cascade-protocol/cascade-cli#16 | embedded `evidence` + `workbench` shapes (`sync-shapes-from-spec.sh`); 992 tests green; note fixtures verified against the embedded shapes |
| cascadeprotocol.org | the-cascade-protocol/cascadeprotocol.org#2 | `evidence/v1-draft` + `workbench/v1-draft` docs (HTML + `cascade-protocol-schemas.md`), `sync-from-spec.sh` + `generate-llms.sh` draft loops, regenerated `llms-full.txt` |
| conformance | the-cascade-protocol/conformance#2 | `fixtures/evidence/` (six facet fixtures) + `fixtures/workbench/` (six note fixtures + one filing-label fixture) with INVENTORY.md; all 14 proven PASS/FAIL against the real validator |
| sdk-typescript | the-cascade-protocol/sdk-typescript#2 | `oa`/`ical`/`skos`/`workbench`/`evidence` namespaces + facet/`userSourceLabel` predicates; drafts excluded from the generated JSON-LD context; 408 tests pass |
| sdk-python | the-cascade-protocol/sdk-python#1 | same namespaces + predicates (snake + camel); VOCAB_VERSIONS draft comment; 207 tests pass |
| cascade-agent | the-cascade-protocol/cascade-agent#13 | system-prompt query patterns for the `notes/` container, evidence facets, and `userSourceLabel`; VOCAB_VERSIONS draft comment |

### 1. `workbench:userSourceLabel` (draft, v1-draft.0.4) — DONE

- **Authored:** `spec/ontologies/workbench/v1-draft/workbench.ttl` (DatatypeProperty,
  `owl:versionInfo 1.0-draft.0.4`, `dct:modified 2026-06-28`).
- **What it is:** the user's chosen filing label for a record (the editable-source
  "File under source" action), folded by the app as an annotation. Distinct from
  the imported `clinical:sourceEHR`.
- **Downstream:**
  - [x] cascadeprotocol.org — `sync-from-spec.sh`, HTML + `cascade-protocol-schemas.md` (#2)
  - [x] conformance — `filing-label-refile.VALID.ttl` re-filed-record fixture (#2)
  - [x] cascade-cli — embedded `workbench` shapes (cascade-cli#16); validates open-world, no shape change required to ship
  - [x] sdk-typescript / sdk-python — predicate registered (sdk-typescript#2 / sdk-python#1)
  - [x] cascade-agent — query pattern (#13)

### 2. `evidence:` verdict taxonomy v2 facet model (draft, v1-draft.0.2) — DONE

- **Authored:** `spec/ontologies/evidence/v1-draft/evidence.ttl` +
  `evidence.shapes.ttl` (`owl:versionInfo 1.0-draft.0.2`, `dct:modified
  2026-07-01`, tag `vocab/evidence-v1-draft.0.2`).
- **What it is:** the grounding outcome moves from the flat 4-value
  `evidence:verdict` to orthogonal facets on the Assertion
  (`evidence:direction` / `basis` / `strength` / `settled` / `reason` object
  properties over closed enumerations, `evidence:confidence` xsd:decimal).
  The facets are the canonical serialized form; the SHACL grounding invariant
  is generalized (SHACL Core). `evidence:verdict` and the `VerdictValue`
  individuals are deprecated, kept one release.
- **Code sync (already done in lockstep, not batched):**
  the consuming application's contracts package (invariant + migration) and
  the consuming application's claim-reification path; its grounding fixtures exercise the
  new shapes against the real validator.
- **Downstream:**
  - [x] cascadeprotocol.org — `sync-from-spec.sh`, HTML + `cascade-protocol-schemas.md` (#2)
  - [x] conformance — facet fixtures ported from the consuming application's grounding fixture set (#2)
  - [x] cascade-cli — embedded `evidence` shapes via `sync-shapes-from-spec.sh` (cascade-cli#16)
  - [x] sdk-typescript / sdk-python — facet predicates (sdk-typescript#2 / sdk-python#1)
  - [x] cascade-agent — query patterns (#13)
- **At v1.0 graduation (do NOT batch-forget):** remove `evidence:verdict` +
  the `VerdictValue` individuals and the legacy SHACL branch; make
  `evidence:settled` `sh:minCount 1`; drop the derived legacy `Verdict` from
  the consuming application's contracts package. Also: mint the JSON-LD context for `evidence:`
  and remove the `DRAFT_CONTEXT_EXCLUDED_PREFIXES` guard in sdk-typescript.

### 3. `workbench:` notes / flags / follow-ups as Web Annotations (draft, v1-draft.0.5) — DONE

- **Authored:** `spec/ontologies/workbench/v1-draft/workbench.ttl` +
  `workbench.shapes.ttl` (`owl:versionInfo 1.0-draft.0.5`, `dct:modified
  2026-07-15`, tag `vocab/workbench-v1-draft.0.5`) + `pod-structure.md` §5.2
  `notes/` container.
- **What it is:** [NOTES-ANNOTATION-VOCAB] — caregiver notes, research flags,
  and follow-ups as ONE `oa:Annotation` substrate distinguished by
  `oa:motivatedBy`; required PROV-O attribution; follow-ups dual-typed
  `cal:Vtodo` with `ical:due` / `ical:status`. One minted term
  (`workbench:followUp`). `InvestigationNote` removed (unshipped).
- **Code sync (lockstep, not batched):** Workbench Phase 9 emits/reads these
  under `notes/`; the contracts package drops the stale `InvestigationNote`
  types in the same PR.
- **Downstream:**
  - [x] cascadeprotocol.org — `sync-from-spec.sh`, HTML + `cascade-protocol-schemas.md` (#2)
  - [x] conformance — valid commenting/questioning/followUp notes + INVALID
        followUp-without-status, commenting-without-body, floating annotation (#2)
  - [x] cascade-cli — embedded `workbench` shapes via `sync-shapes-from-spec.sh` (cascade-cli#16)
  - [x] sdk-typescript / sdk-python — `oa:`/`ical:`/`skos:` predicates + namespaces
        (`workbench:followUp` is a motivation individual, reached via the namespace;
        sdk-typescript#2 / sdk-python#1)
  - [x] cascade-agent — query patterns (`notes/` container, motivation filters) (#13)
- **JSON-LD context:** none yet (drafts get contexts at v1.0 graduation, same as
  the other draft rows; sdk-typescript explicitly excludes draft prefixes from
  the generated context until then).

---

## Pending batch — clinical v1.10 (authored 2026-07-16)

Released-vocab change (`clinical` 1.9 to 1.10), tag `vocab/clinical-v1.10`. Per
the seam table, `spec/` + the `cascade-cli` shape sync happen NOW (so `cascade
validate` knows the terms); the rest of the 7-repo checklist BATCHES here and
runs at the next release boundary. Open-world shapes mean the DATA can ship
before this batch fires. Slice V1 of the graph-retrieval sequenced plan
; it blocks importer slice R3.

**What was authored (the four changes):**

- `clinical:hasEncounter` ObjectProperty (range `clinical:Encounter`) — the
  record-to-encounter edge. FHIR: the `.encounter` Reference(Encounter) element
  on Observation/MedicationRequest/Condition/Procedure/DiagnosticReport/
  DocumentReference.
- `clinical:indicationReference` ObjectProperty (range `rdfs:Resource`, open) —
  the medication-to-condition indication edge, alongside the retained free-text
  `clinical:indication` / `clinical:reasonForUse`. FHIR: `MedicationRequest.reasonReference`.
- `clinical:linkedCondition` ObjectProperty (Condition to Condition) plus
  `owl:deprecated true` on `clinical:linkedConditionIds` (the space-separated
  UUID literal it replaces; retained for backward compatibility).
- `clinical:hasLabResult` `rdfs:range` corrected `clinical:LabResult` to
  `health:LabResultRecord` to match what both importer paths
  actually type.
- Shapes: three open-world `sh:targetSubjectsOf` PropertyShapes (IRI nodeKind,
  class where committed, `sh:Warning`, no minCount). JSON-LD context: the three
  new ObjectProperties as `@type: @id`.

**Synced NOW (not batched):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `clinical=1.10`.
- [x] `cascade-cli` — `sync-shapes-from-spec.sh` (embedded `clinical.ttl` +
      `clinical.shapes.ttl`) + `VOCAB_VERSIONS` `clinical=1.10`. PR:
      the-cascade-protocol/cascade-cli#21 (npm test 1034 green; fresh Synthea
      import validates 20/20 clean against the new shapes).

**Batched (do NOT execute now; run at the next batch, per the `CONTRIBUTING.md` cross-repo sequence, steps 2-7):**

- [ ] `cascadeprotocol.org` — `sync-from-spec.sh`, HTML docs (`docs/clinical/v1/`
      version refs, new property/shape sections, changelog entry) +
      `cascade-protocol-schemas.md` heading/property-count/version-history +
      `docs/index.html` clinical card badge; regenerate `llms-full.txt`.
- [ ] `conformance` — fixtures for `hasEncounter` / `indicationReference` /
      `linkedCondition` (VALID edge + INVALID non-IRI / wrong-class), plus a
      `hasLabResult`→`health:LabResultRecord` range fixture; tag a release.
- [ ] `sdk-typescript` — register the three predicates (`@type: @id`) + the
      `health:LabResultRecord` range in the generated context; `VOCAB_VERSIONS`.
- [ ] `sdk-python` — same predicates (snake + camel) + namespaces; `VOCAB_VERSIONS`.
- [ ] `cascade-agent` — system-prompt query patterns for encounter-grouped
      records, medication indications, and condition links; `VOCAB_VERSIONS`.

**At the batch: `check-downstream-versions.sh` should report `clinical` drift
(repo=1.9, spec=1.10) for cascadeprotocol.org, sdk-typescript, sdk-python,
cascade-agent, conformance, and cascade-sdk-swift until each is brought current;
cascade-cli reads 1.10 immediately after its shape-sync PR merges.**

---

## Pending batch — clinical v1.11 (authored 2026-07-16)

Released-vocab change (`clinical` 1.10 to 1.11), tag `vocab/clinical-v1.11`. A
one-property vocabulary-correctness tweak, folded into the same v1.10 batch when
it fires. Per the seam table, `spec/` + the `cascade-cli` shape sync happen NOW;
the rest batches. Slice R3 of the graph-retrieval sequenced plan.

**What was authored (two changes):**

- `clinical:indicationReference` — dropped the restrictive
  `rdfs:domain clinical:Medication` in favor of the broad-domain comment + SHACL
  pattern the other cross-class edges use. FHIR carries `reasonReference` on
  Procedure / MedicationRequest / MedicationAdministration / Encounter, not only
  medications; the R3 importer materializes indication edges from all three
  wired resource types (Procedure is the common case in the Synthea specimen:
  17 of 19). The `IndicationReferenceEdgeShape` was already domain-free.
- Edge shapes `HasEncounterEdgeShape` + `LinkedConditionEdgeShape` — REMOVED
  their `sh:class` constraints. Cascade stores records in per-type files and the
  validator checks each file independently, so an edge to a sibling-file target
  can never satisfy `sh:class`: it warned on every well-formed, fully-resolving
  edge (all 181 hasEncounter edges of the specimen) and never caught a real
  error. `sh:nodeKind sh:IRI` is kept; target class is enforced at import and can
  be re-checked by a future pod-wide validator. This is what makes `cascade
  validate` clean on a pod carrying the R3 edges.

**Synced NOW (not batched):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `clinical=1.11`.
- [ ] `cascade-cli` — `sync-shapes-from-spec.sh` (embedded `clinical.ttl` +
      `clinical.shapes.ttl`) + `VOCAB_VERSIONS` `clinical=1.11`. PR: (R3 branch).

**Batched (do NOT execute now; fold into the clinical v1.10 batch above — same
7 repos, same release boundary):**

- [ ] `cascadeprotocol.org` — HTML docs + `cascade-protocol-schemas.md`: reflect
      the widened `indicationReference` domain (broad, SHACL-constrained).
- [ ] `conformance` — the `indicationReference` VALID fixture no longer needs a
      `clinical:Medication` subject; add a Procedure-subject VALID edge fixture.
- [ ] `sdk-typescript` / `sdk-python` — no predicate change (already registered
      in the v1.10 batch); bump `VOCAB_VERSIONS` `clinical=1.11` with v1.10.
- [ ] `cascade-agent` — indication query patterns already cover it; bump
      `VOCAB_VERSIONS`.

---

## Pending batch — clinical v1.12 (authored 2026-07-20)

Released-vocab change (`clinical` 1.11 to 1.12), tag `vocab/clinical-v1.12`. One
new ObjectProperty, additive only. Per the seam table, `spec/` + the `cascade-cli`
shape sync happen NOW; the rest batches with the v1.10/v1.11 rows above (same 7
repos, same release boundary). Slice M1 of the graph-meaning plan.

**What was authored (one property + its shape):**

- `clinical:parsedIndicationReference` — `rdfs:subPropertyOf
  clinical:indicationReference`, range `rdfs:Resource`. Marks an indication edge
  the importer DERIVED by parsing a coded/free-text reason on a record (FHIR
  `reasonCode`, or a `clinical:indication` / `clinical:reasonForUse` literal) and
  matching it to a condition record in the same pod, as distinct from
  `clinical:indicationReference` proper, which restates a `reasonReference` the
  source explicitly carried. Subproperty modeling means one traversal over the
  superproperty returns both families while the predicate carries the basis; no
  reification, no RDF-star, so the edge stays a plain triple. Carries NO
  confidence score by design: a deterministic parse of what the record says, not
  structural/temporal inference (which stays query-time, per GM-Q2).
- `ParsedIndicationReferenceEdgeShape` — warning-only, `sh:nodeKind sh:IRI`
  only, no `sh:class`, matching `IndicationReferenceEdgeShape` and the v1.11
  per-file-validation rationale.

Motivation (M1 Phase 0 census, counts only): a real provider export reached via
Apple Health carried 0 `reasonReference` but 50 `reasonCode` instances on
medication/procedure records, 25 of which resolve unambiguously to a condition
record by exact coding identity. Those relations are dropped entirely today.

**Synced NOW (not batched):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `clinical=1.12`.
- [ ] `cascade-cli` — `sync-shapes-from-spec.sh` (embedded `clinical.ttl` +
      `clinical.shapes.ttl`) + `VOCAB_VERSIONS` `clinical=1.12`. PR: (M1 branch
      `feat/graph-meaning-m1-literal-lifting`).

**Batched (do NOT execute now; fold into the clinical v1.10/v1.11 batch above):**

- [ ] `cascadeprotocol.org` — HTML docs + `cascade-protocol-schemas.md`: document
      the stated-vs-parsed indication distinction and the subproperty relation.
- [ ] `conformance` — add a VALID `parsedIndicationReference` edge fixture
      (medication subject to condition target) alongside the v1.11 fixtures.
- [ ] `sdk-typescript` / `sdk-python` — register the new predicate; bump
      `VOCAB_VERSIONS` `clinical=1.12`.
- [ ] `cascade-agent` — teach the indication query pattern that the parsed
      variant exists and must be labeled differently in answers; bump
      `VOCAB_VERSIONS`.

---

## Pending batch — health v2.5 / clinical v1.13 / core v3.4 (authored 2026-08-03)

Three released-vocab changes authored together because they are one change:
defining record classes in `health` is what makes the `clinical` duplicates
deprecable, and the pod manifest in `core` counts the same records. Tags
`vocab/health-v2.5`, `vocab/clinical-v1.13`, `vocab/core-v3.4`. **Additive
vocabulary plus shapes only — no serializer, converter or emitter changed in
any repo.**

**What was authored:**

- `health` 2.4 to 2.5 — 5 record classes (`LabResultRecord`, `ConditionRecord`,
  `AllergyRecord`, `ImmunizationRecord`, `FamilyHistoryRecord`) that serializers
  have emitted since schema 1.3 but the ontology never defined; the 40
  properties they use; 6 wellness container classes as
  `rdfs:subClassOf health:HealthProfile`; 4 sleep-quality named individuals; a
  namespace-boundary note stating that `health:` vs `clinical:` is historical
  and that provenance is carried only by `cascade:dataProvenance`.
- `health.shapes.ttl` 1.1 to 1.2 — 8 new node shapes (the 5 record classes plus
  `DailyVitalReading`, `DailyActivitySnapshot`, `DailySleepSnapshot`).
  Constraint sets lifted from the corresponding `clinical:*` shapes and checked
  against FHIR R4; `sh:Violation` on required fields.
  `HealthProfileShape` now names the 6 wellness containers as explicit
  additional `sh:targetClass` values.
- `clinical` 1.12 to 1.13 — `owl:deprecated true` + `rdfs:seeAlso` on
  `clinical:LabResult`, `Condition`, `Allergy`, `Immunization`. **Not removed:**
  the pod export path is still their sole emitter. Also documents the intended
  FHIR value sets on `clinical:status` and `clinical:interpretation` and records
  why two of them are deliberately unenforced (constraining either is breaking
  for existing pods). No shape changed.
- `core` 3.3 to 3.4 — the pod export manifest vocabulary: 32 previously
  undefined `cascade:` terms. `ExportManifest` as `rdfs:subClassOf dcat:Dataset`
  (DCAT 3), `RecordSummary` as `rdfs:subClassOf void:Dataset` with counts as
  `rdfs:subPropertyOf void:entities`, `InteractionScenario` kept novel.
  `core.shapes.ttl` 1.0 to 1.1 adds shapes for all three.

**Measured against the reference patient pod (19 files):** undefined `health:`
terms 51 to 0, undefined `cascade:` terms 32 to 0, typed subjects matched by
some shape 156 of 448 to 277 of 448. Validation stays 19 of 19 PASS with 0
violations — the pod's data is conformant, what changed is that it is now
actually checked.

**Synced NOW (not batched):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `health=2.5`,
      `clinical=1.13`, `core=3.4`.
- [ ] `cascade-cli` — `sync-shapes-from-spec.sh` (embedded `health.ttl`,
      `health.shapes.ttl`, `clinical.ttl`, `core.ttl`, `core.shapes.ttl`) +
      `VOCAB_VERSIONS`. Note: `src/shapes/health.ttl` has never been synced by
      that script, which syncs full ontologies for `core clinical coverage`
      only; fix the script in the same pass.

**Batched (do NOT execute now; fold into the clinical v1.10/v1.11/v1.12 batch
above — those repos are still at `clinical=1.9`):**

- [ ] `cascadeprotocol.org` — HTML docs + `cascade-protocol-schemas.md`: the
      five record classes are now defined and shaped, so the four "note on type
      discrepancy" blocks in the serialization docs are stale. Retype the
      reference pod's six wellness containers.
- [ ] `conformance` — 26 existing fixtures (`lab-001..007`, `cond-001..007`,
      `allergy-001..006`, `imm-001..003`, `fam-001..003`) become executable
      against real constraints; add wellness fixtures for the 3 daily shapes.
      Bump `VOCAB_VERSIONS`.
- [ ] `sdk-typescript` / `sdk-python` — model files for the 5 record classes,
      JSON-LD context terms, `VOCAB_VERSIONS`.
- [ ] `cascade-agent` — query patterns for the record classes; `VOCAB_VERSIONS`.
- [ ] `cascade-sdk-swift` — `VOCAB_VERSIONS` only. No serializer change: it is
      already emitting the ratified names.

---

## Pending batch — Validation Profile 1.0 + genomics v1-draft.0.5 (authored 2026-08-03)

**No released vocabulary changed and no version in `VOCAB_VERSIONS` moved**, so
the drift checker will keep reporting every repo up to date. The propagation
below is nonetheless real: it changes what two tools are permitted to do, and it
tightens one draft shape that `cascade-cli` embeds a copy of.

**What was authored:** `validation/index.md` (Validation Profile 1.0), the
normative statement of the entailment regime these shapes assume;
`scripts/check-shape-targets.py` and `scripts/test-check-shape-targets.sh`
enforcing it; CI job `shapes`; genomics v1-draft.0.5, the two shape corrections
the check found on its first run. See `CHANGELOG.md` for the rule.

**Synced NOW (not batched):**

- [x] `spec/` — authored (this repo). No `VOCAB_VERSIONS` change: drafts are
      unrowed per D-PATH and no released vocabulary moved.
- [ ] `cascade-cli` — re-sync `src/shapes/genomics.shapes.ttl` so the embedded
      copy carries the `sh:node` and the widened `sh:class`. Until then
      `cascade validate` will not check copy number variants for
      `genomics:dataQualityTier`.

**Batched:**

- [ ] `conformance` — the runner passes the `rdfs:subClassOf` axioms as
      `ont_graph`, which entails more than the implementations it certifies, so
      a fixture can pass the gate and fail in a strict validator. Per profile
      rule V5 every fixture's expected outcome must be reproducible with no
      pre-validation merge. Re-run with the merge removed and confirm no fixture
      outcome changes; any that does was testing the runner's configuration
      rather than the implementation's behaviour. Cite `validation/index.md`
      wherever the inferencing setting lives.
- [ ] `cascade-cli` — cite `validation/index.md` at the shapes-loading site, so
      the (correct, conformant) decision not to entail is recorded as a decision
      rather than an accident. Consider the profile's §6 assertion for vendored
      shapes: every `sh:targetClass` in the bundled copy must resolve to a class
      in the bundled vocabulary.
- [ ] `cascadeprotocol.org` — publish `validation/index.md`; add it to
      `scripts/sync-from-spec.sh`, which currently copies ontologies and
      contexts only.
- [ ] `sdk-typescript` / `sdk-python` / `cascade-agent` — no change. Neither SDK
      validates, and no vocabulary term moved.

---

## Pending batch — core v3.5 (authored 2026-08-09)

**What was authored:** `cascade:sourceIdentity`, the ORIGIN axis — a canonical,
transport-independent identity for the organization a record came from,
scheme-prefixed `org:` / `ns:` / `transport:`. `cascade:sourceSystem`'s comment
narrowed to state it is the INGESTION batch and not a reconciliation key.
`cascade:SourceIdentityShape` added as an open-world `sh:targetSubjectsOf` shape,
so absence is not a finding and pods written before v3.5 validate unchanged.
`VOCAB_VERSIONS` `core=3.5`. Tag `vocab/core-v3.5`.

**Synced NOW (not batched):**

- [x] `spec/` — authored (this repo).
- [ ] `cascadeprotocol.org` — `scripts/sync-from-spec.sh`, HTML docs +
      `cascade-protocol-schemas.md`.
- [ ] `conformance` — fixtures for the three value schemes, including a
      two-transport-one-system pair whose FHIR and C-CDA halves carry the same
      `org:` slug.
- [ ] `cascade-cli` — `scripts/sync-shapes-from-spec.sh` + `VOCAB_VERSIONS`, and
      the emission itself: both converters mint the identity at one chokepoint
      and the reconciler's same-source guard reads it.

**Batched:**

- [ ] `sdk-typescript` — register the `sourceIdentity` predicate and add it to the
      generated JSON-LD context. Neither SDK validates, so nothing is blocked on
      this; a reader of a v3.5 pod simply will not have a typed accessor.
- [ ] `sdk-python` — same, snake and camel spellings.
- [ ] `cascade-agent` — system-prompt query patterns: "records from one
      organization" should read `cascade:sourceIdentity`, not
      `cascade:sourceSystem`.

---

## Pending batch — core v3.6 / health v2.7 / clinical v1.15 (authored 2026-08-14)

Four rulings authored together. Tags `vocab/core-v3.6`, `vocab/health-v2.7`,
`vocab/clinical-v1.15`. Additive and strictly widening; the only new finding
anywhere is at `sh:Warning`. See `CHANGELOG.md` for the full statement.

**What was authored:**

- `core` 3.5 to 3.6 — `cascade:dataAbsentReason` bound to the 15 FHIR
  data-absent-reason codes, with the HL7 v3 NullFlavor mapping table stated on
  the property; `cascade:DataAbsentReasonShape` (core.shapes.ttl 1.5 to 1.6),
  open-world `sh:targetSubjectsOf`. Plus the NORMATIVE canonical form of a
  multi-valued identity input, stated on `cascade:cascadeUri`: dedupe, sort by
  code point, fixed separator, one-element sequence equals the bare scalar,
  and the three separator-independent invariants.
- `health` 2.6 to 2.7 — `health:interpretation`'s `sh:in` gains the fourteen
  data-absent-reason codes it lacked (60 values to 74);
  `health:interpretationSourceCode` (new) and its shape.
  `health.shapes.ttl` 1.3 to 1.4.
- `clinical` 1.14 to 1.15 — `clinical:VitalSignShape`'s interpretation bound to
  the same 74-value set at `sh:Warning` (the ratchet, Violation later);
  `clinical:interpretation`'s `sh:in` gains the same fourteen codes;
  `clinical:interpretationSourceCode` (new) with shapes on the lab and vital
  shapes; `clinical:ProcedureShape`'s name requirement moved to an `sh:or` over
  `clinical:procedureName` and `health:procedureName` plus the new
  warning-severity `clinical:ProcedureNameSpellingShape` (a migration window,
  both halves removed together later). `clinical.shapes.ttl` 1.14 to 1.15.

**Synced NOW (this train):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `core=3.6`,
      `health=2.7`, `clinical=1.15`. `check-shape-targets.py` PASS 3/3;
      regression suite 21/21.
- [x] `cascadeprotocol.org` — `sync-from-spec.sh`, HTML docs +
      `cascade-protocol-schemas.md` (the-cascade-protocol/cascadeprotocol.org#10,
      merged 2026-08-14).
- [x] `conformance` — vital/procedure/absence fixtures, order-shuffle identity
      vectors, `VOCAB_VERSIONS`, `scripts/SPEC_PIN` re-pinned to the merge
      commit (the-cascade-protocol/conformance#13, merged 2026-08-14).
- [x] `cascade-cli` — `sync-shapes-from-spec.sh` + `VOCAB_VERSIONS`, the
      procedure-name emission, the nullFlavor mapping, and the identity
      canonicalization at the set-valued key builders
      (the-cascade-protocol/cascade-cli#57, merged 2026-08-14; released in
      cli 0.17.0).
- [x] `sdk-typescript` — identity canonicalization only
      (the-cascade-protocol/sdk-typescript#7, merged 2026-08-14).

### PENDING_DOWNSTREAM_SYNC — deferred out of this train, deliberately

These are NOT oversights. Each is listed with what fires it.

**ALL ROWS COMPLETED by the follow-through sync, merged 2026-08-15:**
sdk-python#5 (released 3.0.0), sdk-typescript#8 (released 3.0.0),
cascade-agent#17, Cascade-Agentic-Labs/cascade-sdk-swift#4. Two notes against
the rows as written: the sdk-python registration row understated the work
(this train's conformance fixture retarget onto `clinical:Procedure` required
the Procedure record type and validator support, a seven-failure baseline
before any sdk-python change); and the swift outcome is health bumped to 2.7
with core, clinical and coverage HELD with stated per-vocab reasons, so the
drift checker showing those swift rows is honest, not a missed sync.

- [x] **`sdk-python`, delete `_SDK_LEGACY_INTERPRETATIONS`.**
      `src/cascade_protocol/validator/validator.py` carries a one-member
      `frozenset({"elevated"})` special case, accepted because that package put
      the word into the world and the conformance corpus asserted it. The
      removal trigger written on that set is "when those two fixtures move to a
      ratified code". **This train fires it**: the two vital fixtures move to a
      ratified code plus a verbatim source code. Delete the set, the branch that
      reads it, and its test. Nothing else depends on it.
- [x] **`sdk-python`, register the new vocabulary.**
      `cascade:dataAbsentReason`, `health:interpretationSourceCode`,
      `clinical:interpretationSourceCode` (snake and camel); the 74-value
      interpretation list; `VOCAB_VERSIONS` `core=3.6 health=2.7 clinical=1.15`.
- [x] **`sdk-python`, no identity change needed.** Its
      `_canonical_field_value` is the rule this release ratified, and its
      cross-process/cross-directory determinism test already proves the
      invariants. The cross-SDK caveat in that function's docstring — that the
      sequence rule is an extension the other SDKs do not implement — can be
      dropped once the conformance vectors and the two TypeScript
      implementations land.
- [x] **`sdk-typescript`, model-level work.** The identity canonicalization is
      in this train; the MODEL layer is not. Still to do: register
      `dataAbsentReason` and both `interpretationSourceCode` spellings in the
      generated JSON-LD context; extend `LAB_INTERPRETATION_VALUES` from 60 to
      74 and recompute `LAB_INTERPRETATION_CHECKSUM`; and tighten
      `VitalSign.interpretation`, currently typed `VitalInterpretation | string`,
      which accepts anything. Tightening it is what makes the TypeScript SDK
      agree with the shape this train put on `clinical:VitalSignShape`; do it in
      the same round as the sdk-python removal above so the two SDKs stop
      disagreeing about vitals in opposite directions.
- [x] **`cascade-agent`.** Query patterns: a record's absence reason
      (`cascade:dataAbsentReason`) is now answerable and must not be reported as
      "no data"; an interpretation answer should read
      `interpretationSourceCode` alongside `interpretation` so the source's own
      word is quotable; procedure-name queries must read
      `clinical:procedureName` and keep `health:procedureName` until the
      migration window closes. `VOCAB_VERSIONS`.
- [x] **`cascade-sdk-swift`.** `VOCAB_VERSIONS` only, pending confirmation that
      it emits none of the affected predicates.

---

## Pending batch — core v3.7 / health v2.8 / clinical v1.16 / coverage v1.5 (authored 2026-08-27)

Field-coverage remediation, authored in one pass. Tags `vocab/core-v3.7`,
`vocab/health-v2.8`, `vocab/clinical-v1.16`, `vocab/coverage-v1.5`. Additive and
strictly widening; every new finding on a predicate existing pods carry is at
`sh:Warning`. See `CHANGELOG.md` for the full statement.

**What was authored — 24 terms:**

- `clinical` 1.15 to 1.16 — **15 terms** (14 properties, 1 class).
  Encounter: `encounterReason` (repeatable), `admitSource`,
  `dischargeDisposition`, `encounterClassDisplay`, `encounterClassSystem`,
  and the participation structure `EncounterParticipant` (class) +
  `hasParticipant` + `participantName` + `participantRole` +
  `participantRoleCode` (repeatable) + `participantSpecialty`.
  Identity: `businessIdentifier` (domain-free, repeatable).
  Documents: `documentReferenceStatus`, `documentAuthorName` (repeatable),
  `authenticatorName`.
  Two domains DROPPED: `providerName` (was `clinical:CoverageRecord`),
  `verificationStatus` (was `clinical:Condition`).
  One property DEPRECATED: `observationStatus`, superseded by `clinical:status`.
  `clinical.shapes.ttl` 1.15 to 1.16, including new
  `clinical:EncounterParticipantShape`.
- `core` 3.6 to 3.7 — **8 terms** (7 properties, 1 class): `Attachment`,
  `hasAttachment`, `attachmentPath`, `attachmentMediaType`, `contentHash`,
  `hashAlgorithm`, `byteSize`, `attachmentTitle`. Pod layout
  `attachments/{algorithm}/{digest}` is normative in `pod-structure.md`
  section 4.3 (that document goes to 1.1; new sections 4.3 and 7.5).
  `core.shapes.ttl` 1.6 to 1.7: `AttachmentShape`,
  `AttachmentMediaTypeShape`, `HasAttachmentEdgeShape`.
- `coverage` 1.4 to 1.5 — **1 term**: `coverage:status` (FHIR `Coverage.status`,
  required binding to `fm-status`). `coverage.shapes.ttl` 1.1 to 1.2: value at
  `sh:Violation`, presence deliberately not required this version.
- `health` 2.7 to 2.8 — **0 terms**; SHACL only. `health.shapes.ttl` 1.4 to 1.5
  binds `clinical:status` on `LabResultRecordShape` (8 codes) and
  `AllergyRecordShape` (3 codes), and `clinical:verificationStatus` on
  `AllergyRecordShape` (4 codes). All three `sh:Warning`.

**Synced NOW (this train):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `core=3.7`,
      `health=2.8`, `clinical=1.16`, `coverage=1.5`. JSON-LD: 24 terms across
      `contexts/v1/{core,clinical,coverage,cascade}.jsonld`.
      `check-shape-targets.py` PASS 3/3 (T 14, I 14, C 29 examined);
      regression suite 21/21; `check-term-status.py` PASS.

**Steps 2–7, all pending:**

- [ ] `cascadeprotocol.org` — `scripts/sync-from-spec.sh`, then HTML docs +
      `cascade-protocol-schemas.md` for all four vocabularies. The pod-layout
      page needs the new `attachments/` section, which is a doc change beyond
      what the sync script copies.
- [ ] `conformance` — fixtures for: an encounter with reason, hospitalization,
      class display/system, two participants in different roles, and two
      business identifiers; a `clinical:EncounterParticipant`; a document with
      distinct `status` and `documentReferenceStatus`, two authors and an
      authenticator; the five `clinical:status` value sets (one PASS and one
      warning-triggering case each); a `coverage:status` VALID and INVALID
      pair; and a `cascade:Attachment` set covering the three Violation
      constraints plus an absolute path, a `..` path, an uppercase digest and a
      missing media type. Re-pin `scripts/SPEC_PIN`, tag the release.
- [ ] `cascade-cli` — `scripts/sync-shapes-from-spec.sh`, `VOCAB_VERSIONS`, then
      converter adoption: emit the nine encounter facts and the participation
      nodes; move business identifiers off `clinical:sourceRecordId` onto
      `clinical:businessIdentifier` (see the MIGRATION note below); emit
      `DocumentReference.status`, `.author[]` and `.authenticator`;
      emit `Coverage.status`. Reverse converters need the same terms or the
      round trip loses them.
- [ ] `sdk-typescript` — models + predicates + generated JSON-LD context for all
      24 terms; `VOCAB_VERSIONS`.
- [ ] `sdk-python` — namespaces + predicates (snake and camel) for all 24 terms;
      `VOCAB_VERSIONS`.
- [ ] `cascade-agent` — query patterns: a visit's reason and discharge
      disposition are now answerable; participant queries must traverse
      `clinical:hasParticipant` rather than reading a single
      `clinical:providerName`; a document's authors are `documentAuthorName`
      and its signer is `authenticatorName`; "is this document current" reads
      `documentReferenceStatus`, not `clinical:status`. `VOCAB_VERSIONS`.

**MIGRATION, the one thing in this batch that is not purely additive in
practice.** `clinical:sourceRecordId` now states that it holds the
server-assigned logical id only. A converter that has been writing a business
identifier into it must move that value to `clinical:businessIdentifier`. The
two predicates are not interchangeable and a consumer cannot tell them apart
after the fact, so the move belongs in the same change as the emission, not a
later one.

---

## Pending batch — coverage v1.7 (authored 2026-08-31)

SHACL only, **0 terms**. Tag `vocab/coverage-v1.7`. `coverage.shapes.ttl` 1.3 to
1.4: `coverage:InsurancePlanShape` constrains `coverage:sourceRecordId`
(`xsd:string`, `sh:maxCount 1`, `sh:Violation`, no `minCount`). The property has
been declared since coverage v1.3 and no shape anywhere declared an `sh:path`
for it. Closes jayostis/spec#11. See `CHANGELOG.md`.

**Not widening.** Records move from unexamined to examined, so a malformed one
can now be rejected. It cannot reject a record that was conformant: every pod
record carrying this property carries exactly one `xsd:string` value.

**Synced NOW (per the seam table — a released vocab gained a shape, so
`cascade-cli` re-syncs promptly so `cascade validate` documents the constraint):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `coverage=1.7`.
- [ ] `cascade-cli` — `sync-shapes-from-spec.sh` (embedded `coverage.shapes.ttl`)
      + `VOCAB_VERSIONS` `coverage=1.7`. **NOT DONE.**

**Batched (do NOT execute now; run at the next batch, per the `CONTRIBUTING.md`
cross-repo sequence, steps 2-7):**

- [ ] `conformance` — **owes the negative fixture that proves the constraint
      bites**: a `coverage:InsurancePlan` carrying two `coverage:sourceRecordId`
      values, expected to report `sh:MaxCountConstraintComponent` on that path.
      `spec` runs no SHACL validator, so until this exists the constraint is
      asserted by nothing in CI. Verified by hand at authoring time with
      pyshacl 0.30.1 (red against `main`'s shapes, green against these), which
      is evidence and not a test.
- [ ] `cascadeprotocol.org` — `sync-from-spec.sh`, coverage v1 shape docs +
      changelog entry.
- [ ] `sdk-typescript` — **not merely a version bump.** The SDK writes
      `sourceRecordId` as `health:sourceRecordId` for every record type
      (`src/models/common.ts`, `src/terms/clinical-summary.ts`), so a Coverage
      record does not emit `coverage:sourceRecordId` at all today and this
      constraint is unreachable from the SDK. That is the-cascade-protocol
      /sdk-typescript#26, still open. Its `assertCovered`
      (`tests/support/shacl.ts`, on `epic/fixture-verification`) refuses to
      return a verdict for a predicate no vendored shape declares an `sh:path`
      for; this release is what stops that refusal firing on
      `coverage:sourceRecordId` once #26 makes the SDK write it. Sequence: this
      row first, then #26.
- [ ] `sdk-python` — **not examined.** Recorded as unknown, not clear.
- [ ] `cascade-agent` — **not examined.** Recorded as unknown, not clear.

**Two neighbouring gaps this deliberately did NOT close**, recorded here so they do
not vanish. The first now carries its own issue, #18; the second does not yet. #19
is the gate that would have surfaced both without anyone reading the neighbouring
lines:

- `cascade:sourceRecordId` (in `core.ttl`) has the identical defect —
  declared, shaped nowhere — and is live *today* on a VALID conformance
  fixture, `fixtures/core/source-identity-namespace.VALID.ttl`, where a shaped
  `health:LabResultRecord` carries it. Of four namespaced spellings of this one
  concept, two were unjudged; this closes one.
- `coverage:ClaimRecord` and `coverage:BenefitStatement` — the classes the
  property was authored for — remain unshaped, and are **invisible to
  `check-class-coverage.py`**: both are `owl:Class` with no `rdfs:subClassOf`
  at all, so they never enter the PROV-derived population that check walks.
  They are absent from `known-unshaped-classes.json` for that reason rather
  than by exemption. `conformance`'s `KNOWN_FAILURES.json` carries them as
  `UNSHAPED, ownedBy: spec`. The cure is the one the baseline file's own
  `$rule` names: reconsider the superclass, which is the thing that would
  declare these hold record data.
- Neither is in `contexts/v1/coverage.jsonld` either: that file has no
  `sourceRecordId` mapping at all, where `cascade`, `clinical` and `health`
  contexts each do. No new term was added here so the context needed no edit,
  but the omission is real and predates this change.

---

## Pending batch — core v3.11 (authored 2026-09-01)

**2 terms, and one severity correction.** Tag `vocab/core-v3.11` — owed at merge,
not created on the branch. `core.ttl` 3.10 to 3.11 and `core.shapes.ttl` 1.8 to
1.9: `cascade:SubstanceUseConsent` and `cascade:MentalHealthConsent` added as
`cascade:ConsentScope` named individuals, and `cascade:ConsentScopeShape`'s
single property block split so `sh:in` carries the three members at
**`sh:Warning`** while `sh:nodeKind` / `sh:minCount` / `sh:maxCount` keep
`sh:Violation`. Both individuals added to `contexts/v1/core.jsonld`. Closes
jayostis/spec#38. See `CHANGELOG.md`.

**This row supersedes the v3.10 row below rather than replacing it.** v3.10 has
not been propagated to any downstream repo, so every repo that owes v3.10 now
owes 3.10 **and** 3.11 together and should sync once, to `core=3.11`. The v3.10
row is kept for its per-repo findings, which are still accurate.

**Additive and strictly more permissive; nothing that conformed stops
conforming.** Two values that v3.10 rejected now conform, and an IRI outside the
list moves from `sh:Violation` to `sh:Warning`. No pod, fixture or reference
record carries the predicate at all, so no verdict changes anywhere.

**Synced NOW (same seam-table reasoning as v3.10: a released vocab's shape
changed, so `cascade-cli` re-syncs promptly so `cascade validate` stops
rejecting substance-use and mental-health scopes):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `core=3.11`.
- [ ] `cascade-cli` — `sync-shapes-from-spec.sh` (embedded `core.ttl` +
      `core.shapes.ttl`) + `VOCAB_VERSIONS` `core=3.11`. **NOT DONE.** It sits at
      `core=3.6`, so this sync carries 3.7 through 3.11 together. Until it runs,
      the CLI's embedded shapes do not even contain v3.10's `sh:in`, so it is not
      currently rejecting anything this release fixes.

**Batched (do NOT execute now; run at the next batch, per the `CONTRIBUTING.md`
cross-repo sequence, steps 2-7):**

- [ ] `conformance` — **jayostis/conformance#7 is now under-specified and must be
      amended before it is worked.** It was filed against v3.10 and asks for a
      fixture carrying an IRI outside the code list *"expected to report
      `sh:InConstraintComponent` on that path"* — which is still expected, but
      now at **`sh:Warning`**, so the fixture belongs in the `.WARN.ttl`
      polarity and not the negative one. It also needs the two new positives
      (substance-use, mental-health) and a two-valued negative proving
      `sh:MaxCountConstraintComponent` is still a **Violation** — that last one
      is the guard on the block split, and nothing else in any repository can
      assert it. `spec` runs no SHACL validator, so the four graphs in
      jayostis/spec#38's `manual` verification have no durable home until these
      exist. At `core=3.8`.
- [ ] `cascadeprotocol.org` — `sync-from-spec.sh`, core v1 shape docs +
      `schemas.md` + changelog entry. **Not examined** — not cloned on the machine
      this row was written from. Recorded as unknown, not clear.
- [ ] `sdk-typescript` — everything the v3.10 row records still stands, and
      D-CONSENT-1 has since ratified the disposition of the second defect: the
      `TYPE_MAPPING` entry declaring `rdfType: 'cascade:SocialHistoryConsent'`
      treats a code-list VALUE as a pod record type and **should be removed**;
      jayostis/sdk-typescript#43 is the issue and is correct. Its consent module
      can now name all three scopes. At `core=3.8`.
- [ ] `sdk-python` — **not examined.** Recorded as unknown, not clear.
- [ ] `cascade-agent` — **not examined.** Recorded as unknown, not clear.

**Deliberately NOT closed here**, recorded so it does not vanish:

- **`cascade:ConsentRecord`, `consentGrantedAt`, `consentRevokedAt` stay
  unbuilt** — now on ratified authority rather than on an open question.
  D-CONSENT-1 settles their shape (FHIR Consent alignment, in `consents/`) and
  then says building *"waits for the first consumer. Nothing should invent an
  interim representation."* jayostis/spec#20 is the archaeology that prompted it.
- **Presence is still constrained nowhere, at any severity.** Ratchet step 2 is
  unchanged by this release and its precondition — a reference producer emitting
  the predicate — still does not hold. The `sdk-typescript` row above is that
  trigger.
- **`contexts/v1/cascade.jsonld` still carries none of the three scope
  individuals nor `consentScope`**, where `contexts/v1/core.jsonld` now carries
  all four. The parity gap the v3.10 row recorded widens by two terms; it is
  still a separate finding.

---

## Pending batch — core v3.10 (authored 2026-08-31)

**3 terms.** Tag `vocab/core-v3.10` — owed at merge, not created on the branch.
`core.ttl` 3.9 to 3.10 and `core.shapes.ttl` 1.7 to 1.8: `cascade:consentScope`
(`owl:ObjectProperty`, `rdfs:range cascade:ConsentScope`, deliberately no
`rdfs:domain`), `cascade:ConsentScope` (`owl:Class`, a closed code list, **no
`rdfs:subClassOf prov:Entity`** for the reason core v3.9 removed
`cascade:DataProvenance`'s), and `cascade:SocialHistoryConsent` retyped as a
member of it. `cascade:ConsentScopeShape` constrains the VALUE by
`sh:targetSubjectsOf` + `sh:in` and the PRESENCE nowhere. `consentScope` added to
`contexts/v1/core.jsonld` with `"@type": "@id"`. Closes jayostis/spec#5. See
`CHANGELOG.md`.

**Additive; nothing changes verdict.** The shape evaluates only subjects that
already carry the predicate, and no pod, fixture or reference record carries it.
Recorded as measured rather than asserted in the PR: the full `conformance` suite
run against this branch and against `067db6ca`, results diffed, **0 verdict
differences across all 161 fixtures**, the only difference anywhere being
`specHead`.

**Synced NOW (per the seam table — a released vocab gained a property AND a
shape, so `cascade-cli` re-syncs promptly so `cascade validate` documents the
new term):**

- [x] `spec/` — authored (this repo); `VOCAB_VERSIONS` `core=3.10`.
- [ ] `cascade-cli` — `sync-shapes-from-spec.sh` (embedded `core.ttl` +
      `core.shapes.ttl`) + `VOCAB_VERSIONS` `core=3.10`. **NOT DONE.** It sits at
      `core=3.6`, so this sync carries 3.7 through 3.10 together and is not a
      v3.10-only step.

**Batched (do NOT execute now; run at the next batch, per the `CONTRIBUTING.md`
cross-repo sequence, steps 2-7):**

- [ ] `conformance` — **jayostis/conformance#7, filed and blocked on this
      merging** (there is no spec commit to pin until then). Owes three fixtures:
      a positive carrying `cascade:consentScope cascade:SocialHistoryConsent`; a
      negative carrying an IRI outside the code list, expected to report
      `sh:InConstraintComponent` on that path; and one asserting that
      `fixtures/clinical/social-history-smoking.ttl`, which carries no scope,
      still conforms — that third is what proves the open-world half, and nothing
      else in any repository can. `spec` runs no SHACL validator, so until these
      exist `cascade:ConsentScopeShape` is asserted by nothing in CI. At
      `core=3.8`.
- [ ] `cascadeprotocol.org` — `sync-from-spec.sh`, core v1 shape docs +
      `schemas.md` + changelog entry. **Not examined** — not cloned on the machine
      this row was written from. Recorded as unknown, not clear.
- [ ] `sdk-typescript` — **not merely a version bump, and what it has today is
      wrong in two ways rather than one.** `TYPE_MAPPING`'s
      `social-history-consents` entry (`src/vocabularies/namespaces.ts`, lines
      289-293) names `cascade:consentScope` as its `namePred` while the predicate
      is registered nowhere, so the field is silently dropped on serialization —
      that is jayostis/sdk-typescript#43, still open, which records 0 of 4
      declared properties modelled for this term. The **second** defect is in the
      same five lines and is not in #43's scope: that entry declares
      `rdfType: 'cascade:SocialHistoryConsent'`, treating a code-list VALUE as a
      pod record type with its own directory. core v3.10 settles what the term
      is — a `cascade:ConsentScope` individual, the OBJECT of
      `cascade:consentScope` on a record, never the `rdf:type` of one — so the
      row wants removing or reworking, and no issue carries that half yet.
      jayostis/sdk-typescript#42 (derive the record-type table from the
      ontologies) would have prevented it by construction. Its consent module —
      `applyConsent`, `clinicalOnlyPolicy`, `noAccessPolicy` — is pure in-memory
      filtering that writes no RDF; that was not a defect while no predicate
      existed, and **this release is what makes it one**. At `core=3.8`.
- [ ] `sdk-python` — **not examined.** Recorded as unknown, not clear.
- [ ] `cascade-agent` — **not examined.** Recorded as unknown, not clear.

**Three things this deliberately did NOT close**, recorded so they do not vanish.
None carries an issue:

- **Presence is constrained nowhere, at any severity.** Ratchet step 2 is
  `sh:minCount 1` at `sh:Warning` on `clinical:SocialHistoryRecordShape`, and its
  precondition is a reference producer emitting the predicate — which is the
  `sdk-typescript` row above. Step 3 raises it to `sh:Violation` after a release
  in which that Warning is observably absent from conforming output. Each is its
  own vocabulary version. No issue is filed because a dispatchable issue whose
  precondition does not hold is noise; **this row is the trigger.**
- **`contexts/v1/cascade.jsonld` carries neither `consentScope` nor
  `SocialHistoryConsent`**, where `contexts/v1/core.jsonld` now carries both. A
  real parity gap between the two published contexts. It predates this change —
  `SocialHistoryConsent` has been in `core.jsonld` and absent from
  `cascade.jsonld` since core v3.0 — and matters downstream because
  `cascadeprotocol.org` publishes both.
- **`cascade:proxyScope` enumerates its own values in prose only** (`'full'`,
  `'read-only'`, `'investigation-only'`, in the `rdfs:comment` at
  `core.ttl:1559` — the same comment that named `cascade:consentScope` as a live
  sibling for the six months it was undeclared). An enumeration nothing can check
  is one a document can contradict. It is the anti-pattern this release avoided
  rather than the precedent it followed, and it is left alone as a separate
  finding.

---

## Deprecation — `clinical:CoverageRecord` → `coverage:InsurancePlan` (ENTERED RETROACTIVELY 2026-08-30)

**This row is late by roughly six months, and that is the finding it records.** The
deprecation was never entered in this ledger when it happened, so the propagation it
implied was never tracked and never done. Three repositories each recorded a local
symptom — `conformance/KNOWN_FAILURES.json`, two `CLAUDE.md` "Known gaps" sections and a
`KNOWN GAP` source comment in `sdk-typescript` — and none of them referenced the others,
because the row that would have joined them did not exist. It is entered now, with its
boxes in the state they were actually in on 2026-08-30.

**The deprecation has no clean version to name.** `clinical.ttl` labels the class
`DEPRECATED (v1.5+)`, but clinical v1.5 (2026-02-10) **added** `CoverageRecord`: its
changelog entry records eleven new properties and no deprecation at all. `coverage:InsurancePlan`,
the class the label redirects to, arrives in coverage v1.0 on **2026-02-18**, eight days
later. The `v1.5+` label was therefore applied retroactively by an edit this repository's
squashed history cannot date. Anyone following that label to the v1.5 changelog expecting
a deprecation will not find one — which is exactly why this row exists rather than a line
inside a batch section.

**Why nothing caught it.** The cross-repo sequence in `CONTRIBUTING.md` was add-only and
contained the word "deprecat" zero times, so a deprecation passed all seven steps with
every repository still writing the deprecated term. That gap is fixed in the same change
as this row (jayostis/spec#9), and the new "Deprecating a spelling" subsection is now the
checklist this row should have been generated from.

**Note on issue links.** They are owner-qualified. The three issues carrying this work
live on the contributor's forks, where the numbering collides with live, unrelated issues
in `the-cascade-protocol/`; a bare `#7` in this file resolves to the wrong issue when read
from the org repository.

### What each repository owes

- [x] **`spec` — a shape for the retained class.** DONE, clinical v1.18 + v1.19
      (2026-08-30), `clinical:CoverageRecordShape` and
      `clinical:CoverageTypeVocabularyShape` in `clinical.shapes.ttl`
      (jayostis/spec#7).
      `clinical:CoverageRecord` was the only deprecated class in this repository targeted
      by no shape, so every record in that spelling validated `conforms: true` because
      nothing looked at it. clinical v1.13's four deprecated classes all kept their
      shapes; this one never had one to keep. **This bump is itself unpropagated — the
      six downstream steps below the fold have not run for clinical 1.17 → 1.19,
      nor for core 3.8 → 3.9, which landed in the same change (jayostis/spec#12):
      `cascade:DataProvenance` dropped `rdfs:subClassOf prov:Entity`, an axiom that
      classified eleven provenance code-list terms as record data they never hold.
      No term is added, removed or renamed and no shape changes verdict, so the
      downstream obligation is a `VOCAB_VERSIONS` line in each repo rather than
      code — verified against `conformance`, `cascade-cli` and `sdk-typescript`,
      none of which reference `prov:Entity` outside vendored copies of these
      ontologies.**
- [x] **`spec` — the process gap.** DONE, jayostis/spec#9: `CONTRIBUTING.md` now states
      what a deprecation obliges, separately from an addition, and Step 1's shapes
      obligation is no longer conditional on something having been added. A companion
      check (jayostis/spec#6) fails any record-bearing class that no shape targets, so
      the shaped-class half of this cannot recur silently.
- [x] **`conformance` — the fixture is migrated.** DONE, jayostis/conformance#1, PR #4
      merged 2026-08-31 as `bae2f8f`. `fixtures/coverage-001.json` asserted
      `clinical:CoverageRecord` while `reference-patient-pod/clinical/insurance.ttl` in the
      same repository had migrated to `coverage:InsurancePlan` — same subject UUID
      (`urn:uuid:c0vr-0001-aaaa-bbbb-ccccddddeeee`), contradictory classes. The fixture is
      now `coverage:InsurancePlan` and the `UNSHAPED` entry has been removed from
      `KNOWN_FAILURES.json`.

      **This closes one gap and opens a smaller one: no fixture anywhere now asserts
      `clinical:CoverageRecord`, so the shape clinical v1.18 just added is exercised by
      nothing.** Deprecated-and-retained means pods in that spelling still exist and will
      keep being read, so the shape is right to exist — but the corpus no longer proves it
      works. A legacy-read fixture, deliberately retained and labelled as one, is what the
      new `CONTRIBUTING.md` deprecation checklist asks for and what this now needs. Not
      yet filed.

      Three references in `conformance` went stale with that merge and still describe the
      old state: `CLAUDE.md:129` lists the class as a known gap "asserted by
      `coverage-001`" (false on both halves now — the fixture migrated and `spec` has
      shaped the class); `README.md:171`'s `UNSHAPED` table still counts it among nine;
      and `reference-patient-pod/README.md:70` still names `CoverageRecord` in its class
      column. Also not yet filed.
- [ ] **`sdk-typescript` — the SDK cannot emit `coverage:InsurancePlan` at all**
      (jayostis/sdk-typescript#26). `TYPE_MAPPING` resolves the `insurance` pod directory
      to `clinical:CoverageRecord`, and `TYPE_TO_DIR` sends BOTH the `CoverageRecord` and
      `InsurancePlan` spellings there, so both record types serialize as the deprecated
      class. The mapping landed in commit `ed227f0` (2026-02-22) and is present in every
      tagged release from `v1.3.0` onward. The fix is the `DEPRECATED_TYPE_ALIASES`
      pattern this SDK already implements for clinical v1.13's four classes and never
      extended to this one: readers accept both spellings, writers emit only the new one.
- [ ] **`cascade-cli` — contingent, and triggered by the v1.18 bump above.** It vendors
      `src/shapes/clinical.ttl`, which until v1.18 carried the class with no shape.
      Nothing was wrong there — its own test had already retyped off the class — but the
      shape now exists and `sync-shapes-from-spec.sh` has to run for `cascade validate` to
      know about it. No issue yet; this row is the trigger.

### Not checked

`sdk-python`, `cascade-agent` and `cascadeprotocol.org` were **not examined** for this
deprecation. They are not cloned on the machine this row was written from, and an unticked
box is a claim about a repository someone looked at. Treat these three as unknown rather
than clear, and check them before this row is closed out.

---

## Open items

### 1. `clinical:sourceSystemOID` (planned) — NOT yet authored, deferred

> **Superseded in part by core v3.5.** `cascade:sourceIdentity`'s `ns:` tier
> already carries an assigning-authority namespace (the FHIR server base URL or
> the C-CDA `<id>` root OID) as the fallback when no organization is derivable.
> What this item would still add is the RAW OID carried alongside a derivable
> organization, as supplementary provenance and as the key an OID-to-org registry
> would join on. Author it only if that registry work begins; do not author it as
> a second identity axis.

- **Status:** DEFERRED from the 2026-06-28 source-attribution work. The Apple
  Health authoritative-`sourceName` fix (importer reads `export.xml`
  `<ClinicalRecord sourceName>`) made OID-based attribution **supplementary**, not
  load-bearing, so this was not authored this round.
- **What it would be:** carry the raw source-system OID (e.g.
  `urn:oid:1.2.840.114350.1.13.296` = an Epic customer org) alongside the friendly
  `clinical:sourceEHR`, as supplementary provenance + a stable cross-export key for
  reconciliation and the OID→org registry. `clinical:` is a RELEASED vocab (now
  1.11 after the edge-vocab + indication-domain batches above), so authoring it
  bumps `clinical` to 1.12 and triggers the CLI shape sync.
- **Trigger to author:** a non-Apple import (raw FHIR / C-CDA with no Apple
  wrapper) needs OID-based attribution, OR the OID→org registry work begins.
- **Downstream when authored:** full 7-repo checklist (released vocab).

---

_Last updated: 2026-08-31._
