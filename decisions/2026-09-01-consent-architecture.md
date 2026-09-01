# D-CONSENT-1: Consent Architecture

**Status:** Ratified
**Date:** 2026-09-01
**Decided by:** Jed Reinitz
**Prompted by:** an external contributor's archaeology (jayostis/spec#20), which found three
half-built, apparently conflicting statements about where consent lives and correctly refused
to build against any of them.

---

## The question

Nothing in any Cascade vocabulary can say when consent was granted or when it was withdrawn.
Under 42 CFR Part 2 — the regulation the corpus itself cites as the reason the concept exists —
consent is granted at a time, covers a stated scope, and can be revoked. The corpus contained
three partial answers to "where does consent live": a code-list value in `core.ttl`
(`cascade:SocialHistoryConsent`, a named individual under a plural section header with one
member), a RESERVED `consents/` pod directory described as "ODRL consent policies", and a
`SocialHistoryConsent` record class in `sdk-typescript` carrying `consentScope`,
`consentGrantedAt` and `consentRevokedAt` — none of whose predicates any ontology declares.

## The history, corrected

The reconstruction in jayostis/spec#20 reads the record class as downstream invention. The
private repositories invert that. The record class and its three fields were authored first
(sdk-typescript `9ea7c78`, 2026-03-28, together with the matching core v3.0 vocabulary sync to
the protocol site), in the era when vocabulary was authored beside the SDKs and `spec` lagged.
The `spec` commit of 2026-06-16 (`e059b3b`) is a late partial copy of that design, not its
origin: it carried over the scope value and wrote comments referring to `cascade:consentScope`
as though the property existed, but the declaration was never written. The `PodNamespace` enum
that `pod-structure.md` cites does exist — in the private Swift SDK — with `consents`, `acl`,
`profiles` and `shares` cases from the early Solid-alignment phase. Nothing in any repository,
public or private, has ever written a file under `consents/`, and ODRL's entire footprint
across the ecosystem is one doc comment and one table row.

So the "three conflicting intents" are one design (2026-03), one aspirational leftover from
the Solid-alignment phase (ODRL), and one lagging copy (`spec`, 2026-06). This document states
the design once, as one thing.

## The decision

| Question | Decision |
|---|---|
| Is `cascade:consentScope` declared anywhere? | No, and no hidden draft exists. Declare it as an `owl:ObjectProperty` ranging over a new `cascade:ConsentScope` class. The March SDK field comment ("Maps to `cascade:consentScope`") is the original intent; the declaration is the part that never landed. |
| What is the scope value set? | `social-history`, `substance-use`, `mental-health` — the list authored in `9ea7c78`. The enumeration stays OPEN (`sh:in` at `sh:Warning` at most, never `sh:Violation`). Part 2 is US-specific and sensitivity categories grow; reproductive health and genomics are foreseeable members. A closed list missing a member rejects conformant data. |
| Is consent ODRL policies in `consents/`? | **No.** ODRL is machine-enforcement policy language and nothing in this ecosystem enforces policies mechanically; adopting it would be machinery without a consumer. Consent STATE will instead be modelled on **FHIR Consent** (Layer 1, per the defer-to-ratified-standards rule): a future `cascade:ConsentRecord` mapped to `fhir:Consent`, carrying scope, grant time and revocation time — the three fields from the March design, which were correct. The `consents/` directory reservation stays, re-described format-neutrally; the word "ODRL" comes out of `pod-structure.md`. |
| How do scope, pod path, and consent state compose? | They are three layers of one design, not rivals. The scope value ON THE RECORD is a data-sensitivity tag (`clinical.ttl`'s "requires separate consent scope" reads correctly). The pod path (`social-history/`) is container mechanics, so ACLs have something coarse to grip — a consequence of the tag, not the semantics. Consent STATE (grant/revoke, per scope) is records in `consents/`. Enforcement is whoever reads or exports resolving record-scope → active consent → include or redact. `provenance/` holds receipts of what actually left (the egress log, already implemented) — disclosure evidence, never consent state. |

## Consequences

1. `cascade:consentScope` + `cascade:ConsentScope` enter `core.ttl` (the property half is
   already scoped in jayostis/spec#5; the open-enumeration correction above applies).
2. `pod-structure.md`'s `consents/` row is re-described: "Per-scope consent records
   (grant/revocation state; modelled on FHIR Consent). RESERVED." The ODRL wording is removed.
3. `cascade:ConsentRecord` itself is deliberately NOT built yet. The shape is decided (FHIR
   Consent alignment; scope + grantedAt + revokedAt); building waits for the first consumer.
   Nothing should invent an interim representation.
4. `sdk-typescript`'s broken `SocialHistoryConsent` record type should be removed
   (jayostis/sdk-typescript#43 is right: it serializes empty and fails validation). Its three
   fields are not lost — they return as the ratified `ConsentRecord` when it is built.
5. `cascade:SocialHistoryConsent` (the named individual) remains what it always was: a scope
   VALUE, never a record class. The JSON-LD context keeps publishing it as such.

## Why this document exists

The contributor did careful archaeology and still reconstructed the history backwards, because
the design intent lived in repositories they cannot read. Every deep question an outside
contributor asks will hit the same wall. Decisions of this kind are therefore recorded here,
in the public authority repository, from now on.
