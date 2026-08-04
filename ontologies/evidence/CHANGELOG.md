# Cascade Evidence Vocabulary — Changelog

All notable changes to the `evidence:` vocabulary. Draft status: not registered in `spec/VOCAB_VERSIONS` until v1.0 graduation (per the `genomics:` / `advisory:` draft policy).

## v1-draft.0.1 (2026-06-16)

- Initial draft authored in `spec/` for the Cascade Workbench grounding model.
- **Classes:** `Assertion`, `EvidenceLink`, `Citation`, `GroundingActivity`, `VerdictValue`, `StanceValue`.
- **Verdict enum** (named individuals): `Supported`, `Contradicted`, `Unverifiable`, `NeedsLiterature`.
- **Stance enum:** `Supports`, `Contradicts`, `Contextual`.
- ~20 properties across Assertion / EvidenceLink / Citation / GroundingActivity.
- **SHACL:** `AssertionShape` with a **SHACL-Core** grounding invariant (`sh:or`/`sh:not`/`sh:in`: a `Supported`/`Contradicted` verdict requires ≥1 evidence link), `EvidenceLinkShape`, `CitationShape`. Core (not `sh:sparql`) so `rdf-validate-shacl` / `cascade validate` actually enforces it; verified with a build-breaking negative fixture.
- Reuses core provenance (`cascade:extractionModel`, `cascade:extractionConfidence`, `cascade:requiresUserReview`, `prov:wasDerivedFrom`) rather than redefining it.
- Term **"Assertion"** chosen over "Claim" to avoid collision with `coverage:ClaimRecord`.
