# Pending downstream sync ledger

**Purpose.** A vocabulary change is *authored* in `spec/` continuously, but its
propagation to the six downstream repos (the steps 2–7 of the Vocabulary Change
Checklist in the workspace `CLAUDE.md`) is **expensive to do one change at a
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
2. For each ledger row below, run the per-repo steps (CLAUDE.md checklist 2–7).
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
  `packages/claims` `reify()`; Workbench grounding-gate fixtures exercise the
  new shapes against the real validator.
- **Downstream:**
  - [x] cascadeprotocol.org — `sync-from-spec.sh`, HTML + `cascade-protocol-schemas.md` (#2)
  - [x] conformance — facet fixtures ported from the grounding-gate set (#2)
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

**Batched (do NOT execute now; run at the next batch, per CLAUDE.md checklist 2-7):**

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

## Open items

### 1. `clinical:sourceSystemOID` (planned) — NOT yet authored, deferred

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

_Last updated: 2026-07-20._
