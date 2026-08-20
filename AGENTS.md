# AGENTS.md

Canonical source for every Cascade Protocol vocabulary: OWL ontologies, SHACL shapes, JSON-LD contexts, and serialization rules.

## Start here

- `CLAUDE.md` -- repository structure, the three-layer ontology architecture, how shapes relate to ontologies, version bumping.
- `CONTRIBUTING.md` -- the contribution process, and the full seven-step sequence for propagating a vocabulary change across the protocol.
- `validation/index.md` -- the Validation Profile. Read it before authoring or editing any shape.

`CLAUDE.md` and this file describe the same repository. `CLAUDE.md` is loaded automatically by Claude Code; this file exists so any coding agent finds the same instructions.

## Protocol context

<https://cascadeprotocol.org/llms.txt> is the protocol index: install, quick start, data types, MCP server, security model, vocabulary versions, deployment sequence. About 95 lines, meant to be read in full.

Do **not** load `llms-full.txt` from that site. It is roughly 1.3 MB, larger than most working contexts, and as of 2026-08-20 its ontology section is known to be incomplete. The TTL files in this repository are the source of truth.

## Ground rules

- **This repository is where vocabulary is authored, and the only one.** Every other repository carries a derived copy. A change here that is not propagated leaves them stale.
- **A shape never reaches a class through `rdfs:subClassOf`.** SHACL resolves class membership over the data graph; pod records carry `rdf:type` and no schema axioms. Every class you mean to constrain gets its own `sh:targetClass`. This has been authored wrong twice, both times with a comment claiming an inheritance the shape did not have. Run the check rather than trusting the comment.
- **Never weaken a check to make it pass.** The negative controls in `scripts/testdata/` are frozen specimens; their bugs are what make the controls meaningful.
- **Defer to ratified standards.** Map to FHIR, SNOMED CT, LOINC or RxNorm where one covers the concept, and cite the canonical source. Invent vocabulary only where none exists.
- Any change to a `.ttl` file must bump `owl:versionInfo`, update `dct:modified`, add a changelog comment, and update `VOCAB_VERSIONS`. The pre-commit hook enforces the first of those.

## What must be green

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r scripts/requirements.txt

sh scripts/test-check-shape-targets.sh     # the rule's own regression suite
python3 scripts/check-shape-targets.py     # the rule, against this repository

# only if you touched the drift check itself (POSIX sh, CI runs it under dash)
dash scripts/test-check-downstream-versions.sh
```

Both of the first two must exit 0. CI runs them on every PR touching `ontologies/`.

**Activate the venv rather than calling its interpreter by path**: the scripts shell out to `python3`. Without `rdflib` both checks exit 2 and say so rather than passing vacuously, because the check parses Turtle and cannot degrade to a text scan without becoming unsound.

## Conventions

- Commits: `<type>(scope): <vocab>: <description>`, for example `docs(schema): clinical: add ImmunizationRecord class`.
- Tags: `vocab/{name}-v{X.Y}`, for example `vocab/clinical-v1.8`.
- Branch from `main`; open a PR rather than pushing to it.
- Report anything you could not finish, especially downstream steps you lacked access to complete, in the PR body rather than only in a commit message.
