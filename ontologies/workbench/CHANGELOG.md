# Cascade Workbench Vocabulary — Changelog

All notable changes to the `workbench:` vocabulary. Draft status: not registered in `spec/VOCAB_VERSIONS` until v1.0 graduation (per the `genomics:` / `advisory:` draft policy).

## v1-draft.0.8 (2026-09-01)

- **Two record classes say so.** `workbench:Hypothesis` and `workbench:Pin` gain `rdfs:subClassOf prov:Entity`. No term is added, removed or renamed and no definition changed. One of four vocabularies moving together for jayostis/spec#13.
- **What was wrong.** That axiom asserts, in this specification, that instances of a class are stored record data, and `scripts/check-class-coverage.py` reads the `rdfs:subClassOf` chain to decide which classes it examines. Neither class declared any superclass, so the gate reported PASS over both while no shape judged either, and both were absent from `scripts/known-unshaped-classes.json` too -- that file is the gate's OUTPUT, not a filter on it. Both are now in the population and baselined there as owing a shape.
- **The argument is per class, from its properties.** `Hypothesis` is the domain of four properties and the range of `workbench:hasHypothesis`; `Pin` is the domain of two and the range of `workbench:hasPin`. Both persist beyond the session that created them, which is the point of a lifecycle status and of a curated bookmark respectively. `workbench:ImportedConversation` already declared the same superclass.
- **`workbench:Investigation` is NOT declared here, deliberately.** It is the domain of eight properties, declares no `rdfs:subClassOf` either, and so meets the same test and is invisible to the gate for the same reason. jayostis/spec#13 enumerates seven classes across four vocabularies and this is not one of them, so declaring it here would be a change nobody reviewed under an issue that did not scope it. Recorded rather than done.
- **No SHACL change:** no shape is written for either class. What each requires is a separate judgement; the baseline records the debt in the meantime.
- **Draft, so no `VOCAB_VERSIONS` line.** That file registers the six released vocabularies and omits the five drafts; `workbench` joins it at v1.0 graduation. Downstream repos record a dated comment only, per D-PATH.

## v1-draft.0.5 (2026-07-15)

- **Added the notes / research-flags / follow-ups substrate as W3C Web Annotations**. All three artifacts are ONE thing, an `oa:Annotation` over one or more graph nodes, distinguished by `oa:motivatedBy`: caregiver note = `oa:commenting`, research flag = `oa:questioning`, follow-up = `workbench:followUp`.
- **Layer-1 reuse, nothing redeclared:** `oa:` carries body (`oa:TextualBody`), multi-target (`oa:hasTarget`), motivation, and span selectors (`oa:TextQuoteSelector` / `oa:TextPositionSelector` via `oa:SpecificResource`); PROV-O carries required attribution (`prov:wasAttributedTo`, `prov:generatedAtTime`). Follow-ups are dual-typed `cal:Vtodo` and reuse W3C RDF Calendar `ical:due` (optional) + `ical:status` (required, RFC 5545 VTODO enum). `schema:dueDate` was considered and rejected: it does not exist (verified 404; schema.org defines only `paymentDueDate`).
- **Minted exactly one term:** `workbench:followUp`, an `oa:Motivation` with `skos:broader oa:questioning`, per the Web Annotation model's custom-motivation extension rule.
- **Removed** `workbench:InvestigationNote`, `workbench:hasNote`, `workbench:noteText` (draft removal; never emitted by shipping code). An investigation-scoped note is an `oa:Annotation` targeting the `workbench:Investigation`.
- **SHACL (Core only, validator-enforced):** `WebAnnotationShape` (>= 1 target, >= 1 motivation, required attribution + `xsd:dateTime` timestamp), `CommentingBodyShape` (commenting requires a body), `FollowUpShape` (followUp requires `ical:status` in the VTODO enum). Verified against `cascade validate` with positive + negative fixtures (all three violation classes fire; valid multi-target, selector-anchored, and Vtodo notes pass).
- **Pod placement:** notes live in a top-level `notes/` container (`pod-structure.md` §5.2), separate from `annotations/` (record-amendment overlays are edit machinery, not user content).

## v1-draft.0.4 (2026-06-28)

- **Added the filing / organization axis:** `workbench:userSourceLabel` (xsd:string), the user-chosen label for the SOURCE a record is filed under in the Workbench "filing cabinet".
- It is a filing **preference attributed to the user**, carried on a `workbench:Annotation` overlay (`annotationProperty` = `"workbench:userSourceLabel"`, `annotationValue` = the chosen label) whose overlay bears `cascade:SelfReported` provenance.
- It **must not** overwrite the objective imported origin `clinical:sourceEHR`, which is preserved and displayed alongside. The effective source the UI groups by prefers this label when present, else falls back to `clinical:sourceEHR`, else the import-batch tag.
- Orthogonal axis with an **open domain**, mirroring how `workbench:verificationStatus` was added in v1-draft.0.3, so it can file any record.
- **SHACL:** no new shape required — the "file under source" action reuses the already-shaped string predicates `workbench:annotationProperty` / `workbench:annotationValue` on `workbench:Annotation`.

## v1-draft.0.1 (2026-06-16)

- Initial draft authored in `spec/` for the Cascade Workbench desktop investigation app (Layer 3).
- **Classes:** `Investigation`, `ImportedConversation`, `Hypothesis`, `Pin`, `InvestigationNote`, plus status enums.
- **Investigation status enum:** `Active`, `Paused`, `Resolved`, `Archived`.
- **Hypothesis status enum:** `Proposed`, `Supported`, `Retired`, `Excluded` (supports widening + explicitly retiring/excluding hypotheses).
- Properties linking investigations to conversations, hypotheses, pins, and notes; conversation metadata; assertion links into `evidence:`.
- **SHACL:** `InvestigationShape`, `ImportedConversationShape`.
- Deliberately thin: grounding model lives in Layer-2 `evidence:`; phenotype lives in `genomics:`.
