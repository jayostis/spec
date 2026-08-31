# Contributing to Cascade Protocol Specification

Thank you for your interest in contributing to the Cascade Protocol specification. This repository is the canonical source for every Cascade vocabulary: the OWL ontologies, the SHACL shapes, the JSON-LD contexts, and the serialization rules.

**`spec/` is the only place vocabulary is authored.** Every other repository in the protocol carries a copy, a model, a fixture or a prompt derived from what lands here. That is what makes the propagation sequence below load-bearing rather than bureaucratic: a change merged here and not carried downstream leaves five repositories describing a vocabulary that no longer exists, and nothing surfaces it until someone runs the drift check.

## Before you start

Open issues across the protocol, and the subset suitable for a first contribution:

- All open issues: <https://github.com/search?q=org%3Athe-cascade-protocol+is%3Aissue+is%3Aopen>
- Good first issues: <https://github.com/search?q=org%3Athe-cascade-protocol+is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22>

### Types of contribution

**Vocabulary changes (RFC process).** Adding classes or properties, or modifying existing terms, follows a lightweight RFC:

1. **Open an issue** describing the proposed change, including:
   - Which vocabulary is affected (core, health, clinical, coverage, checkup, pots)
   - New classes or properties being added
   - Rationale and use case
   - Mapping to established standards (FHIR, SNOMED CT, LOINC, RxNorm) if applicable
2. **Discussion period**: allow at least 7 days for feedback.
3. **Submit a PR** implementing the change once consensus is reached. It must update every artifact in the checklist below.
4. **Review**: at least one maintainer must approve vocabulary changes.

**Adding SHACL shapes.** When adding validation shapes for new or existing classes:

1. Place shapes in `ontologies/<vocab>/v1/<vocab>.shapes.ttl`.
2. Each shape must define `sh:targetClass` pointing at the ontology class, required-field constraints (`sh:minCount 1`), datatype constraints (`sh:datatype`), and enumeration constraints (`sh:in`) where applicable.
3. Read `validation/index.md` first. The rule in one line: **a shape never reaches a class through `rdfs:subClassOf`.** SHACL resolves class membership over the data graph, and pod records carry `rdf:type` triples without schema axioms, so a subclass axiom confers nothing at validation time. Every class you mean to constrain gets its own `sh:targetClass`. This has been authored wrong twice, in two different vocabularies, both times with a comment claiming an inheritance the shape did not have.
4. Add corresponding fixtures in [conformance](https://github.com/the-cascade-protocol/conformance).

**Documentation fixes.** Typos, clarifications and improved examples are always welcome. Open a PR directly, no RFC needed.

## Development setup

```bash
git clone https://github.com/the-cascade-protocol/spec.git
cd spec

# Install the pre-commit hook. It blocks commits that modify a TTL file
# without bumping owl:versionInfo.
sh scripts/install-hooks.sh

# Python tooling for the shape checks. Use a virtual environment and ACTIVATE it:
# the check scripts shell out to `python3`, so pointing at the venv interpreter
# by path is not enough. A current macOS or Debian-family Python also refuses a
# bare `pip install` outright (PEP 668, "externally-managed-environment").
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r scripts/requirements.txt
```

Without `rdflib` installed both checks exit 2 and say so, rather than passing vacuously. That is deliberate: the check parses Turtle and cannot degrade to a text scan without becoming unsound.

Optionally, to validate against the CLI:

```bash
npm install -g @the-cascade-protocol/cli
cascade validate ontologies/clinical/v1/clinical.shapes.ttl
```

## What must be green before review

Three CI workflows gate this repository, and the `shapes` one runs three independent jobs. Run their commands locally before opening a PR.

```bash
source .venv/bin/activate                  # every check shells out to `python3`

# shapes: three structural rules about this repository's own SHACL. Each pairs
# a regression suite with the rule itself, and all six must exit 0. The three
# rules are deliberately independent -- none can see the others' defect.
sh scripts/test-check-shape-targets.sh     # entailment independence
python3 scripts/check-shape-targets.py

sh scripts/test-check-nested-severity.sh   # nested-shape severity (rule S5)
python3 scripts/check-nested-severity.py

sh scripts/test-check-class-coverage.sh    # record-class shape coverage
python3 scripts/check-class-coverage.py

# drift-checker: only if you touched the downstream drift check itself.
# POSIX sh, not bash. CI runs it under dash to catch bashisms.
dash scripts/test-check-downstream-versions.sh
```

`scripts/check-shape-targets.py` runs on every PR touching `ontologies/`, together with its own negative controls, so a check that has stopped being able to fail is caught here rather than in a consumer. Do not "fix" the frozen specimens in `scripts/testdata/`; their bugs are what make the controls meaningful.

## Commit messages

```
<type>(scope): <vocab>: <description>
```

Examples:

```
docs(schema): clinical: add ImmunizationRecord class
docs(schema): core: bump version to 1.4, add PharmacyInfo
docs(schema): coverage: fix InsurancePlan sh:pattern constraint
fix(shapes): clinical: correct MedicationShape required fields
```

Types:

- `docs(schema)` -- vocabulary or documentation changes
- `fix(shapes)` -- SHACL shape corrections
- `feat(vocab)` -- new vocabulary terms
- `chore` -- maintenance, tooling

Tag format for a ratified vocabulary version: `vocab/{name}-v{X.Y}`, for example `vocab/clinical-v1.8`.

## Opening a pull request

1. Branch from `main`.
2. Make the change, and complete the in-repo checklist below in the same PR.
3. Run the two commands under "What must be green" and confirm both exit 0.
4. Push and open a PR. `.github/PULL_REQUEST_TEMPLATE.md` fills in with the checklist; keep the items and tick them.
5. Say in the PR body which downstream repositories you are able to update and which you are not. A contributor who cannot open PRs against all seven should still say so, so a maintainer can carry the rest rather than discovering the gap later.
6. One maintainer approval is required for vocabulary changes. Documentation-only changes need one review.

## Vocabulary changes: the full cross-repo sequence

This is the authoritative process. It is seven steps and it does not end when the `spec` PR merges.

### Step 1 -- `spec` (this repository)

Before committing any change to an ontology (`.ttl`) file:

- [ ] Bump `owl:versionInfo` (the pre-commit hook blocks the commit otherwise)
- [ ] Update `dct:modified` to today's date
- [ ] Add a changelog comment block at the top of the TTL file
- [ ] Update the corresponding `.shapes.ttl`. This is **not** conditional on something having been added: every class that remains instantiable must be targeted by a shape, including one you are deprecating and retaining. `check-class-coverage.py` enforces it for any class declaring a PROV superclass
- [ ] Update the JSON-LD context (`contexts/v1/{name}.jsonld`) if new terms need `@type` / `@id` mappings
- [ ] Update `VOCAB_VERSIONS` and stage it explicitly: `git add VOCAB_VERSIONS`
- [ ] `python3 scripts/check-shape-targets.py` exits 0
- [ ] `python3 scripts/check-nested-severity.py` exits 0
- [ ] `python3 scripts/check-class-coverage.py` exits 0 -- a new class declaring `rdfs:subClassOf prov:Entity` or `prov:Activity` must be given a shape, or added to `scripts/known-unshaped-classes.json` with an attribution saying who owes it. Baselining is an admission, not a fix: a class in that file is one whose records SHACL reports `conforms: true` over having examined nothing.
- [ ] After committing, tag it: `git tag vocab/{name}-v{X.Y}`

### Steps 2 through 7 -- downstream, in this order

Order matters. Conformance fixtures gate the SDK releases, so a fixture that does not exist yet means an SDK cannot prove it implemented the class correctly.

| # | Target | What to update |
|---|--------|----------------|
| 2 | Documentation site (`cascadeprotocol.org`) | Sync the TTL copies; update the per-vocabulary HTML page (`docs/<vocab>/v1/index.html`), `cascade-protocol-schemas.md` and the version badge on `docs/index.html`. **These artifacts live on the site, not in this repository.** |
| 3 | [`conformance`](https://github.com/the-cascade-protocol/conformance) | Add a valid and an invalid fixture per new class, update the `dataType` enum in `schema/fixture-schema.json`, update `VOCAB_VERSIONS`, tag `conformance-v{YYYY-MM-DD}` |
| 4 | [`cascade-cli`](https://github.com/the-cascade-protocol/cascade-cli) | Run `scripts/sync-shapes-from-spec.sh` (never hand-edit `src/shapes/`), update `VOCAB_VERSIONS`, CHANGELOG, package version |
| 5 | [`sdk-typescript`](https://github.com/the-cascade-protocol/sdk-typescript) | Add `src/models/{class}.ts`, register predicates in `src/vocabularies/namespaces.ts` and `TYPE_MAPPING`, wire serializer, deserializer and JSON-LD context, export from `src/index.ts`, update `VOCAB_VERSIONS` |
| 6 | [`sdk-python`](https://github.com/the-cascade-protocol/sdk-python) | Add `src/cascade_protocol/models/{class}.py`, register predicates in `vocabularies/namespaces.py`, register in serializer **and** deserializer, export from `__init__.py`, update `VOCAB_VERSIONS` |
| 7 | [`cascade-agent`](https://github.com/the-cascade-protocol/cascade-agent) | Update the query patterns and field tables in `src/system-prompt.ts`, update `VOCAB_VERSIONS` |

**Step 2 is maintainer-run.** The documentation site is not a public repository, so an outside contributor cannot open a PR against it. Do the six steps you can and note the site step in your PR; a maintainer completes it. Nothing else in the sequence depends on it.

**Two failure modes worth naming, because both are silent:**

- In `sdk-python`, registering a class in the serializer but not the deserializer makes `parse()` return an empty list rather than an error. A pod full of records reads as an empty pod. Test a round trip, never just a serialize.
- In `conformance`, a fixture that no shape targets is reported `UNSHAPED`: zero constraints ran, so its PASS asserts nothing. A new fixture that passes vacuously is worse than no fixture. `spec` now catches the upstream half of this itself -- `scripts/check-class-coverage.py` fails a record-bearing class that no shape targets -- but only for classes declaring a PROV superclass, and only against a baseline of 34 that predate it. A fixture can still land on an unshaped class; `UNSHAPED` remains the place that is seen.

### Deprecating a spelling -- what the seven steps do not ask

The sequence above is add-only. Every obligation in it is phrased as an addition, so a deprecation can be authored, pass all seven steps, and leave every downstream repository still writing the deprecated term with every box ticked. That is not hypothetical: `clinical:CoverageRecord` was superseded by `coverage:InsurancePlan` and six months later `spec` had no shape for it, `conformance`'s `coverage-001` still asserted it while the reference pod in the same repository had migrated off it, and every `sdk-typescript` release still wrote it for both record types. The one deprecation that did complete -- clinical v1.13's four classes -- completed on someone's attention, not on process.

**Reading and writing move in opposite directions, and this is the whole rule.** A deprecated spelling stops being *written* at once and stays *readable* indefinitely, because pods already contain it and a pod is not migrated by a release note. Every obligation below follows from that asymmetry.

`sdk-typescript`'s `DEPRECATED_TYPE_ALIASES` is the reference implementation: readers resolve a requested type to its new RDF type *and* to any deprecated spelling listed there, while `TYPE_MAPPING` carries no entry for the deprecated classes, so nothing in that SDK can produce one. Copy that shape rather than inventing another.

When a release deprecates a class or property, it owes this in addition to the seven steps:

- [ ] **`spec` -- the deprecated class KEEPS its shape**, for as long as it remains readable. A deprecated class with no shape is worse than an undeprecated one: SHACL reports `conforms: true` over its records having examined nothing, so the data nobody is maintaining is also the data nobody is checking. Retaining a class and dropping its constraints is the one combination that must never ship.
- [ ] **`spec` -- the deprecation gets its own `PENDING_DOWNSTREAM_SYNC.md` row**, not one line inside a batch section. A batch row tracks what was authored; a deprecation's open question is what is still being *emitted*, which is a different list with different owners and a much longer life.
- [ ] **Every downstream writer stops emitting it.** Name each one: converters, importers, both SDKs' serializers and type tables, the agent's query patterns. "Nothing writes this any more" is a claim to verify per repository, not to assume from the deprecation.
- [ ] **Every downstream reader keeps accepting it**, and there is a test proving a record in the old spelling still round-trips. A reader that drops the old spelling silently deletes data from a pod on read-modify-write.
- [ ] **`conformance` -- every fixture asserting the old spelling is resolved explicitly**, either migrated to the new one or deliberately retained as a legacy-read case that says so in its notes. Leaving it unexamined is what produced a fixture and a reference pod in one repository asserting contradictory classes for the same subject UUID.
- [ ] **The migration window has a stated end**, or an explicit statement that there is none. "Retained for backward compatibility" with no horizon is how a temporary spelling becomes permanent.

**A deprecation is not additive, so it does not batch the way an addition does.** The argument for batching -- open-world shapes mean data can ship before the shapes catch up -- does not hold here. Every day the old spelling keeps being written is another day of data that will need the migration run over it again.

### Not every change fires all seven steps at once

Propagating one change through six repositories is expensive, so authored changes
accumulate and the full sync runs in a batch at a release boundary.
`PENDING_DOWNSTREAM_SYNC.md` is the ledger of what is authored and not yet propagated.
Add your change to it in the same PR when you cannot carry the sequence yourself.

Batching is safe because Cascade shapes are open-world (not `sh:closed`): a tool can
emit a new predicate and the Pod still passes `cascade validate` before that predicate
reaches the embedded shapes. The data can ship as soon as `spec` defines the term.

Two consequences worth knowing:

- **Draft vocabularies do not fire the sequence at all.** A `v1-draft` namespace is not
  listed in `VOCAB_VERSIONS` and gates no downstream release. Terms accrue in draft; the
  seven steps run when a draft is promoted to a released `vN`.
- **When a released vocabulary gains a property**, `spec` and `cascade-cli`'s embedded
  shapes are the two to sync promptly, so `cascade validate` documents the new term.
  The rest can batch.

### The drift check

At any point, from a `spec` checkout with the downstream repositories cloned as siblings:

```bash
sh scripts/check-downstream-versions.sh
```

It refreshes each repository's remote-tracking refs before reading them, so a sync that merged a moment ago is seen immediately rather than reported as drift. Besides drift itself, two conditions fail the run, both because they mean a repository was not actually checked: a downstream repository **not present** on disk, and a repository whose **fetch failed**, whose verdict prints as `UNVERIFIED`.

`VOCAB_NO_FETCH=1` skips fetching for a deliberate offline run and labels every verdict as computed from unrefreshed refs. Do not use it to make a red gate green.

## Design principles

When proposing new vocabulary terms:

1. **Defer to ratified standards.** Map through an established standard wherever one exists (FHIR, SNOMED CT, LOINC, RxNorm) and cite the canonical source in the issue. Author novel vocabulary only where no standard covers the concept.
2. **Three-layer mapping.** Every data type maps through established standards at Layer 1, domain vocabulary at Layer 2 (`health:` for wellness and device data, `clinical:` for EHR data), and patient-facing vocabulary at Layer 3 (`checkup:`, `pots:`).
3. **Provenance-first.** All data carries provenance metadata (`cascade:dataProvenance`). New classes must support the standard provenance values.
4. **Local-first.** Vocabulary design must not require network access for validation or processing.
5. **Minimal but complete.** Add only what is needed. Each property should have a clear use case in at least one consuming application.

## Protocol context

<https://cascadeprotocol.org/llms.txt> is the index of protocol context: install, quick start, supported data types, the MCP server, the security model, current vocabulary versions and this deployment sequence. It is about 95 lines and is meant to be read in full, by a person or an agent.

There is also a `llms-full.txt` on that site. **Do not load it.** It is roughly 1.3 MB, larger than most working contexts, and as of 2026-08-20 its ontology section is known to be incomplete. Read the TTL files in this repository instead; they are the source of truth by definition.

## Questions?

Open a [discussion](https://github.com/the-cascade-protocol/spec/discussions) for questions about the specification, vocabulary design, or mapping to external standards.
