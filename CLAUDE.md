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
    index.md                      # Serialization conventions
  pod-structure.md                # Pod directory layout (repo root, not nested)
  contexts/v1/
    cascade.jsonld                # Every vocabulary in one context
    core.jsonld                   # Per-vocabulary contexts
    health.jsonld
    clinical.jsonld
    coverage.jsonld
    checkup.jsonld
    pots.jsonld
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

### A `@context` has no comments, so a section header IS a term definition

Every non-keyword key in a `@context` is a term definition, and its value must be an IRI, a compact IRI, or a keyword. JSON has no comment syntax and JSON-LD adds none, so the familiar workaround — a key nobody will collide with — does not work here:

```json
"__comment_core": "=== Core Vocabulary (cascade:) ===",
```

That is a term whose IRI is a sentence, and a conformant processor rejects **the whole file** over it. Not the one entry: all 716 terms in `cascade.jsonld` were unreachable because six of them were headings.

Three of the seven published contexts shipped that way and stayed broken for months. `json.load` succeeds on all of them — they are valid *JSON*, so an editor, a linter and a JSON syntax check all report them fine. Only expansion objects, and nothing in this repository expanded them.

```sh
python3 scripts/check-context-validity.py       # the rule
sh scripts/test-check-context-validity.sh       # its regression suite
```

Two things to know before changing that check:

1. **Do not rewrite it against `rdflib`.** rdflib is already pinned here and parses JSON-LD, so it is the obvious instrument; it also accepted all three broken files without complaint. `PyLD` is pinned separately for strictness, and control 6 of the suite fails if the two are consolidated.
2. **It asserts that a context LOADS, never that a term maps to the right IRI.** A context resolving `dateOfBirth` to the wrong predicate is valid JSON-LD and passes. That is a different question, and an open one.

If you want a section marker, `@` followed by **letters only** is ignored by a processor — `@commentCore` works, `@comment_core` fails exactly as the original did. Prefer no marker: the terms under a heading already carry the prefix it names.

### Record-bearing is DECLARED with `cascade:RecordClass`, never inferred

A class whose instances a Pod stores carries `a cascade:RecordClass` (core v3.13):

```turtle
health:AllergyRecord a owl:Class, cascade:RecordClass ;
```

That triple is the only machine-readable statement of "instances of this class are
stored records". `scripts/check-class-coverage.py` keys on it to decide which classes
owe a shape. Membership is the triple and nothing else — **not inherited**. A subclass
of a marked class needs its own marker, for the same reason a parent's shape does not
reach a child.

**Do not read `rdfs:subClassOf prov:Entity` as this claim.** It is PROV-O alignment and
confers nothing here. That misreading was the rule through core v3.12, in the checker
and in `known-unshaped-classes.json`'s `$rule`, and two vocabulary changes were made on
the strength of it (#12, #13). [ASK-05](https://github.com/jayostis/spec/issues/34)
ruled it out:

> The axiom is PROV-O alignment … Your shape-coverage checker should key on that, or on
> an explicit list, never on `prov:Entity`, which will keep catching alignment axioms.

Measured at the time: 110 classes reached a PROV root and **96 of them were registered
nowhere as stored records**. PROV superclasses stay and stay true; they simply do not
answer this question. Never add or remove one to change what the gate sees — that is the
defect, not a fix.

`cascade:DataProvenance` is the worked example of the two claims being separate: it
declares `rdfs:subClassOf prov:Entity` (true — a classification is a thing PROV can
reference) and carries no marker (also true — nothing is ever typed with it).

```sh
python3 scripts/check-class-coverage.py            # the rule
sh scripts/test-record-class-declarations.sh       # incl. the guard on the above
python3 scripts/check-record-class-registry.py     # pod-structure.md must agree
python3 scripts/check-context-coverage.py          # every record class has a JSON name
```

Two things a new record class needs beyond the marker: an entry in its vocabulary's
context **and** in `cascade.jsonld` (or `check-context-coverage.py` fails), and either a
shape or a `known-unshaped-classes.json` entry (or `check-class-coverage.py` fails).

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
- [ ] Run `python3 scripts/check-context-validity.py` and get exit 0 — the `contexts` CI job runs it, and its regression suite, on every PR touching `contexts/`. **Required whenever you touch a context, which is not the same trigger as the rest of this list**: a context change need not accompany a `.ttl` change, and this was the one gate with no `.ttl` in front of it
- [ ] If you added a class whose instances a Pod stores, mark it `a cascade:RecordClass` and run all four record-class checks — `check-class-coverage.py`, `test-record-class-declarations.sh`, `check-record-class-registry.py`, `check-context-coverage.py`. A new record class needs the marker, a context entry in **both** its own context and `cascade.jsonld`, and either a shape or a `known-unshaped-classes.json` entry. Three separate gates will tell you which one you missed
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
