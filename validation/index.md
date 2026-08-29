# Cascade Protocol Validation Profile

**Version:** 1.0
**Date:** 2026-08-03
**Status:** Normative
**Organization:** Cascade Agentic Labs LLC

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

---

## 1. Scope

[SHACL](https://www.w3.org/TR/shacl/) is a validation language, not a validation *configuration*. Two implementations can both conform to the SHACL specification and still return opposite verdicts on the same data and the same shapes, because the specification leaves the choice of pre-validation inferencing to the deployment. That freedom is deliberate in SHACL. It is not acceptable in Cascade Protocol, where a Pod is expected to travel between a command-line tool, a mobile SDK, a conformance suite and a third-party consumer and be judged the same way by each.

This document fixes that freedom. It states the **entailment regime** Cascade Protocol shapes assume, what a conforming validator must and must not do about it, and what a shape author must do so that the two never come apart.

It applies to:

- every `.shapes.ttl` file published in this repository;
- every implementation that claims to validate Cascade Protocol data;
- every conformance suite that certifies such an implementation.

It does not change any vocabulary. It states a property the vocabularies already have and makes that property testable.

---

## 2. The problem this profile solves

`sh:targetClass` selects its focus nodes by class membership. [SHACL §2.1.3.2](https://www.w3.org/TR/shacl/#targetClass) defines those nodes as the *SHACL instances* of the named class, and [§1.1](https://www.w3.org/TR/shacl/#dfn-shacl-instance) defines a node `n` as a SHACL instance of class `C` **in a graph `G`** when one of the SHACL types of `n` in `G` is `C`, where SHACL types follow `rdf:type/rdfs:subClassOf*` within `G`. For validation, `G` is the data graph. The subclass chain is therefore read from the data being validated, not from the ontology that declares it.

[SHACL §1.5](https://www.w3.org/TR/shacl/#entailment) is explicit that this is a deployment choice rather than a fixed one: "full RDFS inferencing is not required", and "SHACL processors MAY, but are not required to, support entailment regimes".

Cascade Protocol records carry `rdf:type` triples. They do not carry `rdfs:subClassOf` triples; schema axioms live in the ontology files and are not serialized into Pod data (see [`serialization/index.md`](../serialization/index.md) and [`pod-structure.md`](../pod-structure.md)). The consequence is exact and easy to miss:

> A subclass axiom that lives only in an ontology file confers no shape coverage on the subclass. A shape targeting `Parent` does not fire on a node typed `Child`, even where `Child rdfs:subClassOf Parent` is declared.

A validator that merges the ontology into the data graph first, or that applies RDFS entailment, sees the opposite. Both behaviours are defensible readings of SHACL. The result is that the same file is valid under one implementation and invalid under another, and neither implementation is doing anything wrong.

This is not hypothetical. Measured on this repository's own shapes: a `genomics:CopyNumberVariant` missing `genomics:dataQualityTier` and missing every stable identifier was reported **conforming** by a validator that performs no entailment and **non-conforming, with two Violation-severity results**, by one that merges the subclass axioms. `genomics:CopyNumberVariant rdfs:subClassOf genomics:Variant` was declared, and `genomics:CopyNumberVariantShape` said in its own comment that `VariantShape`'s constraints "apply transitively". They did not. The rule below, and the check that enforces it, exist because a shape can assert an inheritance it does not have and nothing will contradict it.

---

## 3. Normative rules

### 3.1 Rules for validators

**V1. Class membership is read from the data graph.**
A conforming validator MUST resolve `sh:targetClass`, `sh:class`, and every other class-membership test over the data graph as supplied, per SHACL §1.1 and §2.1.3.2. No shape published by this specification requires entailment to reach a correct verdict, and none ever will; a validator that performs no inferencing whatsoever is fully conforming.

**V2. Entailment is permitted, and is an extension.**
A validator MAY apply RDFS entailment, OWL reasoning, or a pre-validation merge of ontology files into the data graph. This is an implementation extension, not a requirement. A validator that does so SHOULD say so in its output or its documentation, so that two reports can be compared knowingly.

**V3. Entailment MUST NOT change the verdict.**
For data conforming to the Cascade Pod serialization rules (that is, data carrying `rdf:type` triples and no schema axioms), applying V2 MUST NOT change the conformance verdict. A file that conforms without entailment MUST conform with it, and a file that fails without entailment MUST fail with it.

V3 is a constraint on **shapes**, not on validators. It is satisfiable only because §3.2 requires shapes to be entailment-independent. A measured verdict difference between an entailing and a non-entailing validator is therefore a **defect in the shapes** and SHOULD be reported as such against this repository. It is never grounds for changing a validator's inferencing configuration.

**V4. Reports MAY differ where verdicts do not.**
V3 constrains the verdict and the set of *failing* focus nodes. It does not constrain result multiplicity or result granularity. An entailing validator may apply a superclass shape to a node both directly and through the subclass shape's `sh:node` reference, and so may report the same underlying problem more than once; an implementation of `sh:node` may report one aggregate result where another reports each nested result. Consumers MUST NOT treat a difference in result count as a difference in verdict.

**V5. A conformance suite is bound by V1.**
A suite that certifies Cascade validators MUST be able to reproduce each fixture's expected outcome under V1, with no pre-validation graph merge and no inferencing. A suite MAY additionally run its fixtures with entailment enabled, but a fixture whose expected outcome is reachable *only* with entailment does not test what implementations do, and MUST NOT be used to certify them.

**V6. Cascade shapes graphs MUST NOT declare `sh:entailment`.**
SHACL §1.5 lets a shapes graph require an entailment regime with `sh:entailment`, and obliges a processor that does not support the named regime to **signal a failure** rather than validate. No shapes file published here declares it, and none may: doing so would convert every strictly conforming, non-inferencing validator from a correct implementation into a hard error. Implementers can rely on the absence of `sh:entailment` from these files as a guarantee, not an accident.

### 3.2 Rules for shape authors

**S1. Every class a shape means to constrain carries an explicit `sh:targetClass`.**
Targeting is never inherited. If `Child rdfs:subClassOf Parent` and a shape targets `Parent`, that shape does not reach `Child`; either the same shape MUST additionally name `Child` in `sh:targetClass`, or another shape MUST target `Child`. SHACL's implicit class targets ([§2.1.3.3](https://www.w3.org/TR/shacl/#implicit-targetClass), where a shape is itself declared an `rdfs:Class`) satisfy S1 equally, since they are stated in the shapes graph rather than inferred. This repository does not currently use them.

**S2. Constraint inheritance MUST be stated, not inferred.**
Where a subclass is required to satisfy its superclass's constraints, the shapes MUST say so by one of two idioms, both already in use here:

*One shape, several targets.* The same node shape names the parent and every child:

```turtle
health:HealthProfileShape a sh:NodeShape ;
    sh:targetClass health:HealthProfile ;
    sh:targetClass health:ActivityData ;
    sh:targetClass health:SleepData ;
    # ... one line per subclass
    sh:property [ ... ] .
```

*One shape per class, joined by `sh:node`.* Each child shape names the parent shape:

```turtle
clinical:ProgressNoteShape a sh:NodeShape ;
    sh:targetClass clinical:ProgressNote ;
    sh:node clinical:ClinicalDocumentShape ;   # explicit; applies in every validator
    sh:property [ ... ] .                       # progress-note-specific additions
```

Prefer the second where the subclass adds constraints of its own, and the first where a single constraint set covers the whole family. Both are entailment-independent: `sh:node` is a constraint component evaluated on the focus node, so it applies whether or not the validator entails.

The second idiom carries a hazard the first does not, and it is not optional to know about it: see **S5**.

**S3. `sh:class` value constraints MUST enumerate the acceptable subclasses.**
`sh:class` is resolved exactly as `sh:targetClass` is. `sh:class Parent` accepts only nodes explicitly typed `Parent`; a value typed `Child` is rejected by a non-entailing validator and accepted by an entailing one. Where subclasses are acceptable values, list them:

```turtle
sh:property [
    sh:path genomics:hasComponent ;
    sh:or (
        [ sh:class genomics:Variant ]
        [ sh:class genomics:CopyNumberVariant ]
    ) ;
] .
```

The same applies to `sh:qualifiedValueShape` when its value shape is a class test.

**S4. Do not write shapes that depend on `sh:targetSubjectsOf` / `sh:targetObjectsOf` to compensate.**
Those targets select by predicate, not by class, so they are already entailment-independent and remain available. They are not a substitute for S1: a predicate-based target constrains the nodes that use a predicate, not the nodes of a class.

**S5. A shape referenced by `sh:node` or `sh:qualifiedValueShape` MUST carry only `sh:Violation`-severity constraints.**
SHACL defines conformance as an [empty validation result](https://www.w3.org/TR/shacl/#conformance-checking), and that definition does not consult severity. A nested `sh:Warning` or `sh:Info` is still a result, so the value node does not conform, so the referring constraint reports a failure — at *its* severity, which is `sh:Violation` unless declared otherwise. Publishing a soft constraint on a shape that anything reaches by `sh:node` therefore republishes it as a rejection on every referring class, and the nested result may not be surfaced at all: the reader gets an opaque `sh:NodeConstraintComponent` naming no field.

This is a direct hazard of the S2 `sh:node` idiom, and it has already been shipped. clinical v1.16 declared the `clinical:status` and `clinical:documentReferenceStatus` value sets at `sh:Warning` on `clinical:ClinicalDocumentShape`; six document subtype shapes reach it by `sh:node`, and all six *rejected* status values the release said would only be reported. Two independent engines agreed. clinical v1.17 is the fix.

Where a class family needs a constraint softer than `sh:Violation`, put it on a shape that reaches its classes by `sh:targetClass` — the S2 *first* idiom — and leave the `sh:node` referent carrying Violation-severity constraints only:

```turtle
# The sh:node referent: Violation-severity constraints only.
clinical:ClinicalDocumentShape a sh:NodeShape ;
    sh:targetClass clinical:ClinicalDocument ;
    sh:property [ sh:path clinical:sourceEHR ; sh:minCount 1 ] .

# The soft constraint, reaching the same classes by target rather than by reference.
clinical:DocumentStatusShape a sh:NodeShape ;
    sh:targetClass clinical:ClinicalDocument ;
    sh:targetClass clinical:ProgressNote ;
    # ... one line per class in the family
    sh:property [ sh:path clinical:status ; sh:in ( ... ) ; sh:severity sh:Warning ] .
```

**Declaring `sh:severity` beside the reference is NOT the remedy** and MUST NOT be used as one. Severity attaches to the shape a constraint belongs to, not to one nested result, so `sh:node X ; sh:severity sh:Warning` demotes the whole of `X` — structural violations included. A document missing a required field would stop being rejected.

One further consequence, for the case where a family needs *different* soft constraints per class: two shapes binding the same path over overlapping target sets will double-report. Class targets follow `rdfs:subClassOf*` wherever the axioms are present in the validated graph, so a shape targeting a parent also reaches every child there and not in a validator that omits the axioms. Bind each path once, over every class in the family, and vary the message rather than the shape.

### 3.3 Rule for ontology authors

**O1. `rdfs:subClassOf` stays, and means what it always meant.**
Nothing above discourages declaring subclass relationships. They make `rdfs:domain` and `rdfs:range` declarations true rather than contradicted, they carry the model's meaning to reasoning consumers, and they are the basis on which S1 and S2 identify what needs an explicit target. What they are not is a validation mechanism. Adding a subclass axiom changes what the ontology *means*; it changes nothing about what any validator *checks*.

---

## 4. Why this way

The alternative rule would be to mandate the merge: require every conforming validator to load the ontology files and entail before validating. It was considered and rejected.

- **It moves correctness into configuration.** Under the merge rule, a validator is correct only if it loaded the right ontology files, at the right versions, in the right way. Every consumer acquires a way to be silently wrong that has nothing to do with the data or the shapes.
- **It is unenforceable where validation actually happens.** Much Cascade validation runs inside a library embedded in someone else's application, on a device, with no ability to fetch or bundle a full ontology set. A rule that such an implementation cannot follow is a rule that will be ignored.
- **It widens the conformance surface.** Certifying "does this implementation validate correctly" becomes "does this implementation validate correctly *and* resolve, version, and merge ontologies correctly." The second half is a larger and more fragile problem than the first.
- **The chosen rule costs one line per class.** An explicit `sh:targetClass` is a single line in a file this project already maintains, written once by the party that already knows the model. That is a far better place to pay the cost than in every consumer.

The chosen rule also has the property that it cannot be quietly violated: whether a shape depends on entailment is decidable from the shapes and ontologies alone, with no data and no validator. §5 decides it on every change.

---

## 5. How this is enforced

`scripts/check-shape-targets.py` evaluates the three shape-author rules over every ontology and shapes file in this repository, and fails the build if any is broken. It parses the files with [rdflib](https://rdflib.dev/) and reasons over the graph structure; it runs no validator and needs no data.

| Assertion | Rule | What it proves |
|---|---|---|
| **T** target closure | S1 | No class sits under a targeted superclass without a target of its own. |
| **I** constraint-set equivalence | S2 | Where a class and its superclass are both targeted, the subclass reaches the superclass's constraints explicitly (shared shape, or `sh:node`). Checked once per *shape* targeting the superclass, not once per class pair. |
| **C** value-class closure | S3 | The set of classes accepted at any one `sh:class` site is closed under `rdfs:subClassOf`. |

Run it directly:

```sh
python3 -m pip install -r scripts/requirements.txt
python3 scripts/check-shape-targets.py
```

The check reports how many cases each assertion examined and **fails if any assertion examined none**. An assertion with nothing to inspect has proven nothing, and reporting that as a pass is the failure mode this whole document exists to prevent.

Assertion **I** is evaluated per (class, superclass, shape-targeting-the-superclass). The weaker per-class-pair form it replaced was unsound as soon as a class was targeted by more than one shape, which S5 makes routine: a second shape naming both the class and its superclass satisfied the pair while saying nothing about whether the *first* shape's constraints reached the subclass. Under the old form, deleting `clinical:ProgressNoteShape`'s `sh:node` reported PASS, because `clinical:DocumentStatusShape` targets both classes. The negative control that exercises exactly that deletion is what caught it.

`scripts/test-check-shape-targets.sh` is the check's own regression suite. Every assertion in it is paired with a negative control: a scratch copy of the repository with one entailment dependency deliberately reintroduced, which the check MUST catch, naming the offending class. An assertion that has never been observed failing is not evidence.

`scripts/check-nested-severity.py` enforces **S5**, and is deliberately a separate check: S5 is not an entailment question, so `check-shape-targets.py` is structurally unable to see it, and the defect S5 describes went out in a release under a green build. It fails any `sh:node` or `sh:qualifiedValueShape` reference into a shape carrying `sh:Warning` or `sh:Info`.

```sh
python3 scripts/check-nested-severity.py
sh scripts/test-check-nested-severity.sh
```

`scripts/nested-severity-baseline.json` enumerates the sites that predate the check, each naming the vocabulary that owns the fix. It is a gate input, not a filter: every reference is still examined and reported, and the run fails both when an unlisted site appears **and** when a listed site stops occurring, so the list can only shrink and shrinking it is an explicit committed edit. Nothing in it is acceptable long-term. Its regression suite reintroduces the clinical v1.16 authoring and requires a named failure, checks that `sh:Info` escalates identically, checks that a severity declaration on the reference does *not* silence the finding, and exercises the baseline in both directions.

The CI job `shapes` runs both checks and both regression suites on every pull request that touches `ontologies/`. These are the only automated tests of this repository's own shapes: nothing here runs a SHACL validator, so a regression in an `sh:pattern` or an `sh:in` member is still invisible to this repository and is caught, if at all, by the `conformance` repository's fixtures. Closing that gap is the intended next step.

---

## 6. Consequences for downstream implementations

**Validators.** No change is required of an implementation that already validates without inferencing; it was conforming and remains so. An implementation that merges ontologies keeps that behaviour under V2 and, by V3, will agree with the others on every verdict. Both SHOULD cite this document where their inferencing behaviour is configured, so the choice is visible rather than incidental.

**Conformance suites.** Per V5, a fixture's expected outcome must be reproducible with no pre-validation merge. A suite that currently merges subclass axioms should verify that removing the merge does not change any fixture's outcome; where it does, the fixture was testing the suite's configuration rather than the implementation's behaviour.

**Shape consumers that bundle copies of these shapes.** Bundled copies inherit these guarantees only if they are complete. A partial sync that drops a `sh:targetClass` line silently reintroduces exactly the gap S1 forbids, so consumers that vendor shapes SHOULD assert that every `sh:targetClass` in their bundled copy resolves to a class in their bundled vocabulary.

---

## 7. References

- [Shapes Constraint Language (SHACL)](https://www.w3.org/TR/shacl/). W3C Recommendation. §1.1 (SHACL instance), §1.5 (relationship to RDFS inferencing, `sh:entailment`), §2.1.3.2 (`sh:targetClass`), §4.1.1 (`sh:class`), §4.7.1 (`sh:node`).
- [RDF Schema 1.1](https://www.w3.org/TR/rdf-schema/), for `rdfs:subClassOf`.
- [`serialization/index.md`](../serialization/index.md), how Cascade data is serialized, and §1.7 on the role of the shapes files.
- [`pod-structure.md`](../pod-structure.md), Pod layout; the reason data graphs carry no schema axioms.
