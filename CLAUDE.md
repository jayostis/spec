# Cascade Protocol Specification - Agent Context

## Repository Purpose

This repository contains the canonical source-of-truth for all Cascade Protocol vocabularies: OWL ontology files, SHACL validation shapes, serialization rules, and JSON-LD contexts.

## Repository Structure

```
spec/
  ontologies/
    core/v1/core.ttl              # Core ontology (identity, provenance, Pod structure)
    core/v1/core.shapes.ttl       # SHACL shapes for core classes
    health/v1/health.ttl          # Health/wellness ontology
    health/v1/health.shapes.ttl   # SHACL shapes for health classes
    clinical/v1/clinical.ttl      # Clinical/EHR ontology
    clinical/v1/clinical.shapes.ttl
    coverage/v1/coverage.ttl      # Insurance/coverage ontology
    coverage/v1/coverage.shapes.ttl
    checkup/v1/checkup.ttl        # Patient-facing summary ontology
    checkup/v1/checkup.shapes.ttl
    pots/v1/pots.ttl              # POTS-specific ontology
    pots/v1/pots.shapes.ttl
  serialization/
    turtle-rules.md               # Serialization conventions
    pod-structure.md              # Pod directory layout
  contexts/
    cascade-v1.jsonld             # JSON-LD context
```

## Key Concepts

### Three-Layer Ontology Architecture

- **Layer 1 (External)**: Established standards -- FHIR, SNOMED CT, LOINC, RxNorm
- **Layer 2 (Domain)**: Cascade vocabularies -- `health:` for wellness/device, `clinical:` for EHR
- **Layer 3 (Patient-facing)**: Application vocabularies -- `checkup:` for summaries, `pots:` for specialized apps

### Namespace URIs

All namespaces follow the pattern: `https://ns.cascadeprotocol.org/<vocab>/v1#`

### How Shapes Relate to Ontologies

Each `.ttl` ontology file defines classes and properties (OWL). Each `.shapes.ttl` file defines SHACL validation constraints for those classes. Shapes reference ontology classes via `sh:targetClass` and constrain their properties.

Example relationship:
- `clinical.ttl` defines `clinical:MedicationRecord` as an OWL class with properties
- `clinical.shapes.ttl` defines `clinical:MedicationShape` targeting `health:MedicationRecord` with constraints like required fields, datatypes, and value enumerations

### Shapes MUST be entailment-independent

Read `validation/index.md` before authoring or editing a shape. The rule in one line: **a shape never reaches a class through `rdfs:subClassOf`.**

SHACL resolves class membership over the DATA graph. Pod records carry `rdf:type` triples and no schema axioms, so a subclass axiom that lives in an ontology file confers nothing at validation time. A validator that merges the ontology first sees the opposite, which means the same file can be valid under one implementation and invalid under another.

Three consequences when you touch a shapes file:

1. Every class you mean to constrain gets its own `sh:targetClass`. Declaring `Child rdfs:subClassOf Parent` does not put `Child` under `ParentShape`.
2. Constraint inheritance is written, not inferred: either one shape names parent and children in `sh:targetClass`, or the child's shape names the parent's shape with `sh:node`.
3. `sh:class` works the same way. `sh:class Parent` rejects a value typed `Child`; enumerate the acceptable subclasses with `sh:or`.

This has been authored wrong twice, in two different vocabularies, both times with a comment claiming an inheritance the shape did not have. Run the check rather than trusting the comment:

```sh
python3 -m pip install -r scripts/requirements.txt
python3 scripts/check-shape-targets.py          # the rule
sh scripts/test-check-shape-targets.sh          # the rule's own regression suite
```

`rdfs:subClassOf` itself stays. It is what makes `rdfs:domain` / `rdfs:range` true and what the check uses to work out which classes need an explicit target. It is simply not a validation mechanism.

### A shape reached by `sh:node` may carry ONLY `sh:Violation`

Rule S5 in `validation/index.md`. SHACL conformance is an **empty result set**, and that definition does not read severities: a nested `sh:Warning` makes the value node non-conforming, so the referring `sh:node` constraint fires at *its* severity, which is `sh:Violation`. A Warning published on a shape that anything reaches by `sh:node` is therefore delivered to every referring class as a rejection — and often as an opaque `sh:NodeConstraintComponent` naming no field.

This shipped. clinical v1.16 put two Warning-severity value sets on `clinical:ClinicalDocumentShape`, and all six document subtypes rejected values the release said were advisory. clinical v1.17 fixed it by moving them onto shapes that reach the same classes by `sh:targetClass`.

**Declaring `sh:severity` next to the `sh:node` is not the fix.** Severity belongs to a shape, not to one nested result, so it demotes the whole referenced shape including its structural violations.

```sh
python3 scripts/check-nested-severity.py        # the rule
sh scripts/test-check-nested-severity.sh        # its regression suite
```

`scripts/known-severity-escalations.json` holds the pre-existing sites (checkup, health, draft genomics). It can only shrink: the check fails on an unlisted site AND on a listed site that no longer occurs. Do not add to it to make a build green — the entry is a committed admission that a consumer is being handed a rejection where the vocabulary promised a warning.

Note what neither check does: **spec runs no SHACL validator**, so a regression in an `sh:pattern` or an `sh:in` member is invisible here. Behavioural verification lives in the `conformance` repository.

### Version Bumping

When modifying an ontology:
1. Bump `owl:versionInfo` in the TTL file
2. Update `dct:modified` date
3. Add a changelog comment at the top of the file
4. Update the corresponding shapes file if new properties are added

## MANDATORY: Pre-Commit Checklist for Vocabulary Changes

**This repo is the gate. Incomplete commits cause downstream drift.**

Before committing any change to an ontology (`.ttl`) file, you MUST:

- [ ] Bump `owl:versionInfo` — the pre-commit hook will block the commit if you don't
- [ ] Update `dct:modified` to today's date
- [ ] Add a changelog comment block at the top of the TTL file
- [ ] Update the corresponding `.shapes.ttl` if new classes/properties were added
- [ ] Update JSON-LD context (`contexts/v1/{name}.jsonld`) if new terms need `@type` / `@id` mappings
- [ ] Update `VOCAB_VERSIONS` file for this vocabulary — stage it with `git add VOCAB_VERSIONS`
- [ ] Run `python3 scripts/check-shape-targets.py` and get exit 0 (the `shapes` CI job runs it, and its regression suite, on every PR touching `ontologies/`)
- [ ] Run `python3 scripts/check-nested-severity.py` and get exit 0 — same CI job. Required whenever you add or move an `sh:severity`, and whenever you add an `sh:node`
- [ ] Tag the commit: `git tag vocab/{name}-v{X.Y}` after committing

After committing, complete the downstream update sequence (in order):

1. **cascadeprotocol.org** — run `scripts/sync-from-spec.sh`, then update HTML docs + schemas.md
2. **conformance** — add fixtures for new classes/properties; tag the release
3. **cascade-cli** — run `scripts/sync-shapes-from-spec.sh`, update `VOCAB_VERSIONS`
4. **sdk-typescript** — add model files, update predicates + context, update `VOCAB_VERSIONS`
5. **sdk-python** — add model files, update namespaces + predicates, update `VOCAB_VERSIONS`
6. **cascade-agent** — update system prompt query patterns, update `VOCAB_VERSIONS`

Run `scripts/check-downstream-versions.sh` at any time to see which repos are behind.

The checker refreshes each repo's remote-tracking refs before reading them, so a
sync that merged upstream a moment ago is seen immediately rather than reported as
drift until someone happens to pull. Two conditions fail the run besides drift
itself, both because they mean a repo was not actually checked:

- a downstream repo that is **not present** on disk
- a repo whose **fetch failed**, whose verdict is printed as `UNVERIFIED`

For a deliberate offline run, `VOCAB_NO_FETCH=1` skips fetching and labels every
verdict as computed from unrefreshed refs. Do not use it to make a red gate green.

The checker has its own regression suite, which CI runs on every change to it:

```sh
sh scripts/test-check-downstream-versions.sh
```

It is hermetic (throwaway git repos in a temp dir, no network, no real downstream
repo is read). Its negative controls run against frozen pre-fix specimens in
`scripts/testdata/`; do not "fix" those files, their bugs are what make the
controls meaningful.

## Commit Conventions

```
docs(schema): <vocab>: <description>
```

Tag format: `vocab/{name}-v{X.Y}` (e.g., `vocab/clinical-v1.8`)

## Hook Setup

After cloning, install the pre-commit hook:
```sh
sh scripts/install-hooks.sh
```

The hook will block commits that modify TTL files without bumping `owl:versionInfo`.

## Related Repositories

- [conformance](https://github.com/the-cascade-protocol/conformance) -- Test fixtures derived from these shapes
- [cascade-cli](https://github.com/the-cascade-protocol/cli) -- CLI bundles copies of shapes files; run `sync-shapes-from-spec.sh` after updates
- [sdk-typescript](https://github.com/the-cascade-protocol/sdk-typescript) -- Implements serialization per these ontologies
- [sdk-python](https://github.com/the-cascade-protocol/sdk-python) -- Python implementation
- [cascade-agent](https://github.com/the-cascade-protocol/cascade-agent) -- System prompt must reflect current vocabulary
