# Cascade Protocol Specification

[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)
[![Spec Status](https://img.shields.io/badge/status-stable-green.svg)]()

The canonical specification for the Cascade Protocol: ontology files (OWL/Turtle), SHACL validation shapes, serialization rules, and JSON-LD contexts.

## Overview

Cascade Protocol defines a three-layer semantic vocabulary for health data:

| Layer | Namespace | Prefix | Purpose |
|---|---|---|---|
| Core | `https://ns.cascadeprotocol.org/core/v1#` | `cascade:` | Identity, provenance, Pod structure |
| Health | `https://ns.cascadeprotocol.org/health/v1#` | `health:` | Wellness and device data |
| Clinical | `https://ns.cascadeprotocol.org/clinical/v1#` | `clinical:` | EHR/clinical record data |
| Coverage | `https://ns.cascadeprotocol.org/coverage/v1#` | `coverage:` | Insurance and coverage |
| Checkup | `https://ns.cascadeprotocol.org/checkup/v1#` | `checkup:` | Patient-facing health summaries |
| POTS | `https://ns.cascadeprotocol.org/pots/v1#` | `pots:` | POTS-specific test data |

Each vocabulary maps to established standards (FHIR, SNOMED CT, LOINC, RxNorm) while providing patient-owned, local-first semantics.

## Repository Structure

```
spec/
  ontologies/
    core/v1/
      core.ttl              # Core ontology (OWL)
      core.shapes.ttl       # SHACL validation shapes
    health/v1/
      health.ttl            # Health ontology
      health.shapes.ttl     # SHACL shapes
    clinical/v1/
      clinical.ttl          # Clinical ontology
      clinical.shapes.ttl   # SHACL shapes
    coverage/v1/
      coverage.ttl          # Coverage ontology
      coverage.shapes.ttl   # SHACL shapes
    checkup/v1/
      checkup.ttl           # Checkup ontology
      checkup.shapes.ttl    # SHACL shapes
    pots/v1/
      pots.ttl              # POTS ontology
      pots.shapes.ttl       # SHACL shapes
  serialization/
    turtle-rules.md         # Turtle serialization conventions
    pod-structure.md        # Pod directory layout spec
  validation/
    index.md                # Validation Profile: the entailment regime shapes assume
  contexts/
    cascade-v1.jsonld       # JSON-LD context for all vocabularies
  CHANGELOG.md
```

## Vocabulary Versions

| Vocabulary | Current Version | Classes | Properties |
|---|---|---|---|
| Core | 2.8 | PatientProfile, Address, EmergencyContact, PharmacyInfo, Pod, Container | ~25 |
| Health | 2.3 | HealthProfile, WellnessStatistic | ~15 |
| Clinical | 1.7 | ClinicalDocument, ClinicalSection, ClinicalNarrative, ProgressNote, DischargeSummary, ConsultationNote, LaboratoryReport, ImagingReport, VisitSummary, Medication, Allergy, LabResult, Condition, Immunization, Procedure, VitalSign, MedicationUseEpisode, Supplement, LabTestSeries, CoverageRecord (deprecated), Encounter, MedicationAdministration, ImplantedDevice, ImagingStudy | ~40 |
| Coverage | 1.3 | InsurancePlan, Deductible, CopaySchedule, ClaimRecord, BenefitStatement, DenialNotice, AppealRecord, DenialReasonCode | ~12 |
| Checkup | 3.2 | CheckupSummary | ~10 |
| POTS | 1.4 | POTSTest, HeartRateMeasurement | ~8 |

## SHACL Shapes

Each vocabulary includes SHACL shapes that define validation constraints:

- **Required fields** (`sh:minCount 1`) -- e.g., every MedicationRecord must have a `medicationName`
- **Value enumerations** (`sh:in`) -- e.g., `dataProvenance` must be one of `ClinicalGenerated`, `DeviceGenerated`, `SelfReported`, `AIGenerated`
- **Pattern constraints** (`sh:pattern`) -- e.g., `schemaVersion` must match `^[0-9]+\.[0-9]+$`
- **Datatype constraints** (`sh:datatype`) -- e.g., `isActive` must be `xsd:boolean`

Validate data against shapes using the [Cascade CLI](https://github.com/the-cascade-protocol/cli):

```bash
cascade validate record.ttl
```

**Shapes are entailment-independent.** SHACL resolves class membership over the data graph, so a shape that reached a class only through an `rdfs:subClassOf` axiom would fire in a validator that merges ontologies and stay silent in one that does not, so the same file would be valid under one implementation and invalid under another. Every class these shapes constrain therefore carries an explicit `sh:targetClass`, and constraint inheritance is stated with `sh:node` rather than inferred. [`validation/index.md`](validation/index.md) states the rule normatively; `scripts/check-shape-targets.py` enforces it on every change.

## Namespace Prefixes

All Cascade Protocol data uses these canonical prefixes:

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix clinical: <https://ns.cascadeprotocol.org/clinical/v1#> .
@prefix coverage: <https://ns.cascadeprotocol.org/coverage/v1#> .
@prefix fhir:    <http://hl7.org/fhir/> .
@prefix sct:     <http://snomed.info/sct/> .
@prefix loinc:   <http://loinc.org/rdf#> .
@prefix rxnorm:  <http://www.nlm.nih.gov/research/umls/rxnorm/> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:    <http://www.w3.org/ns/prov#> .
```

## Links

- [Full Documentation](https://cascadeprotocol.org/docs/)
- [Schema Reference](https://cascadeprotocol.org/docs/cascade-protocol-schemas/)
- [Conformance Test Suite](https://github.com/the-cascade-protocol/conformance)
- [CLI Tool](https://github.com/the-cascade-protocol/cli)

## License

This specification is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
