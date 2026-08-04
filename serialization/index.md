# Cascade Protocol Serialization Specification

**Version:** 2.0 (Phase 2)
**Date:** 2026-02-19
**Status:** Descriptive with normative examples
**Organization:** Cascade Agentic Labs LLC

---

## 1. Introduction

### 1.1 Purpose and Scope

This document specifies how Cascade Protocol health data types are serialized to RDF/Turtle and JSON-LD formats. It serves as the authoritative guide for SDK implementers who need to produce or consume Cascade Protocol data.

**This specification covers all Cascade Protocol data types:**

**Core Clinical Records (Phase 1):**

1. Medications (clinical `MedicationRecord` and wellness supplements)
2. Conditions (`ConditionRecord`)
3. Allergies (`AllergyRecord`)
4. Lab Results (`LabResultRecord`)
5. Vital Signs (clinical `VitalSignRecord`)
6. Patient Profile / Demographics (`PatientProfile`)

**Extended Records (Phase 2):**

7. Immunizations (`ImmunizationRecord`)
8. Procedures (`ProcedureRecord`)
9. Family History (`FamilyHistoryRecord`)
10. Coverage / Insurance (`CoverageRecord` / `InsurancePlan`)
11. Wellness Observations (Heart Rate, Blood Pressure, Activity, Sleep, HRV, VO2 Max, Body Measurements)
12. Comprehensive Provenance Model (W3C PROV-O integration)
13. Pod Structure Conventions (cross-reference)

Each data type section includes a properties table, annotated Turtle examples, JSON-LD equivalents, provenance patterns, SHACL validation constraints, and multi-system coding guidance where applicable.

### 1.2 Conformance Levels

This specification uses a **descriptive-with-normative-examples** approach:

- **MUST** (Normative): SDKs MUST produce SHACL-valid output when validated against the published SHACL shapes files (`clinical.shapes.ttl`, `health.shapes.ttl`, `core.shapes.ttl`). The SHACL shapes are the normative validation layer.
- **SHOULD** (Recommended): SDKs SHOULD produce output matching the reference Turtle patterns shown in this specification. These examples represent the canonical serialization produced by the reference Swift SDK.
- **MAY** (Optional): SDKs MAY include additional properties beyond those listed, provided they do not conflict with the defined vocabulary.

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

### 1.3 How to Read This Specification

Each data type section follows this structure:

1. **Description** -- What the data type represents and its FHIR alignment
2. **Properties Table** -- All predicates with URI, data type, cardinality, and description
3. **Turtle Example** -- Annotated serialization showing every property in context
4. **JSON-LD Equivalent** -- The same record expressed as JSON-LD
5. **Provenance** -- How `cascade:dataProvenance` applies to this type
6. **SHACL Constraints** -- Key validation rules from the shapes files
7. **Multi-System Coding** -- How standard terminology codes (RxNorm, SNOMED, LOINC, ICD-10) are used

### 1.4 Turtle Notation Primer

If you are new to RDF, here is a minimal Turtle primer to help you read the examples in this specification.

**Triples.** RDF data consists of subject-predicate-object triples. In Turtle syntax:

```turtle
<subject> <predicate> <object> .
```

The period (`.`) ends a statement. A semicolon (`;`) continues with the same subject but a new predicate-object pair:

```turtle
<urn:uuid:abc-123> a health:MedicationRecord ;  # "a" is shorthand for rdf:type
    health:medicationName "Metformin" ;           # string literal
    health:isActive true ;                        # boolean literal
    health:startDate "2024-01-15T00:00:00Z"^^xsd:dateTime .  # typed literal
```

**Prefixes.** Compact URIs use declared prefixes:

```turtle
@prefix health: <https://ns.cascadeprotocol.org/health/v1#> .
# Now health:medicationName expands to https://ns.cascadeprotocol.org/health/v1#medicationName
```

**Blank nodes.** Anonymous inline resources use square brackets:

```turtle
<urn:uuid:abc-123> cascade:emergencyContact [
    a cascade:EmergencyContact ;
    cascade:contactName "Jane Doe"
] .
```

**Lists.** Ordered collections use parentheses:

```turtle
health:affectsVitalSigns ("heartRate" "bloodPressure") .
```

**Typed literals.** Explicit data types use the `^^` notation:

```turtle
cascade:dateOfBirth "1985-03-15"^^xsd:date .
cascade:computedAge "40"^^xsd:integer .
```

### 1.5 Namespace Prefixes

All examples in this specification use the following namespace prefix declarations. SDK implementations MUST use these exact namespace URIs.

```turtle
@prefix cascade:  <https://ns.cascadeprotocol.org/core/v1#> .
@prefix health:   <https://ns.cascadeprotocol.org/health/v1#> .
@prefix clinical: <https://ns.cascadeprotocol.org/clinical/v1#> .
@prefix coverage: <https://ns.cascadeprotocol.org/coverage/v1#> .
@prefix fhir:     <http://hl7.org/fhir/> .
@prefix sct:      <http://snomed.info/sct/> .
@prefix loinc:    <http://loinc.org/rdf#> .
@prefix rxnorm:   <http://www.nlm.nih.gov/research/umls/rxnorm/> .
@prefix icd10:    <http://hl7.org/fhir/sid/icd-10-cm/> .
@prefix ucum:     <http://unitsofmeasure.org/> .
@prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:     <http://www.w3.org/ns/prov#> .
```

**IMPORTANT -- LOINC namespace:** The canonical LOINC namespace for this specification is `http://loinc.org/rdf#`. The ontology files and SDK implementations contain historical inconsistency (`https://loinc.org/rdf/` in `health.ttl`, `http://loinc.org/` in `ClinicalRDFSerializer.swift`). This specification establishes `http://loinc.org/rdf#` as the canonical form. Future SDK releases will converge on this namespace.

### 1.6 Provenance Model Overview

Every Cascade Protocol resource MUST include a `cascade:dataProvenance` triple that classifies how the data was generated. The provenance taxonomy is defined in `core.ttl` and follows a two-branch hierarchy:

```
cascade:DataProvenance
    |
    +-- cascade:ConsumerGenerated           # Non-clinical setting
    |       +-- cascade:DeviceGenerated     # Wearable/medical device
    |       +-- cascade:SelfReported        # Patient-entered data
    |       +-- cascade:ConsumerWellness    # Aggregated wellness platform
    |
    +-- cascade:ClinicalGenerated           # Clinical setting
            +-- cascade:EHRVerified         # Imported from EHR system
            +-- cascade:ScannedDocument     # From scanned/photographed document
            +-- cascade:AIExtracted         # Extracted by AI from unstructured text
```

In Turtle, provenance is expressed as an object property linking to a provenance class:

```turtle
<urn:uuid:abc-123> cascade:dataProvenance cascade:EHRVerified .
```

Typical mappings by data source:

| Data Source | Provenance Class |
|---|---|
| Epic MyChart / Cerner (HealthKit FHIR) | `cascade:EHRVerified` |
| Apple Watch / Fitbit / consumer device | `cascade:DeviceGenerated` |
| Patient manual entry in app | `cascade:SelfReported` |
| Apple Health aggregated data | `cascade:ConsumerWellness` |
| AI extraction from scanned lab report | `cascade:AIExtracted` |

### 1.7 Relationship to SHACL Shapes and Conformance Suite

Each data type in this specification has a corresponding SHACL shape that serves as the machine-readable validation contract. The SHACL shapes files are:

- `core.shapes.ttl` -- Patient Profile, Address, EmergencyContact, PharmacyInfo, AdvanceDirectives
- `clinical.shapes.ttl` -- Medication, Allergy, LabResult, Condition, VitalSign, Immunization, Procedure, MedicationUseEpisode, Supplement
- `health.shapes.ttl` -- HealthProfile, VO2MaxStatistics, HRVStatistics, BPStatistics, MetricTrend, ActivitySnapshot, SleepSnapshot, SelfReport
- `coverage.shapes.ttl` -- InsurancePlan

The shapes use three severity levels:

| SHACL Severity | RFC 2119 Mapping | Meaning |
|---|---|---|
| `sh:Violation` | MUST | Data is invalid without this. Blocks operations. |
| `sh:Warning` | SHOULD | Important for completeness. Shown prominently to users. |
| `sh:Info` | MAY | Suggested enrichment. Nice to have. |

**Validation workflow:** To validate serialized data, load the appropriate shapes file and the data file into a SHACL validator (e.g., Apache Jena, pySHACL, or TopBraid). The validator will report violations, warnings, and informational messages according to the severity levels above.

**Entailment.** Cascade shapes are authored so that no RDFS entailment or ontology merge is needed to reach a correct verdict, and so that performing one does not change the verdict either. A validator that loads only the shapes file and the data file is fully conforming. The rule, its rationale, and what it requires of shape authors and of conformance suites are stated normatively in [`validation/index.md`](../validation/index.md); implementers whose validator has an inferencing setting should read it before choosing one.

---

## 2. Medications

### 2.1 Description

Medications represent prescription drugs, over-the-counter medications, and other pharmaceutical products. The Cascade Protocol distinguishes between two medication-related types:

- **`health:MedicationRecord`** -- A source record representing a single medication entry from one data source (EHR import, patient entry, pharmacy claim). This is the primary medication serialization type produced by the SDK's `ClinicalRDFSerializer`. Multiple source records may be reconciled into a `MedicationUseEpisode` for longitudinal tracking.
- **`clinical:Supplement`** -- A dietary supplement, OTC product, or herbal remedy with explicit regulatory status. Supplements are intentionally separate from medications due to different regulatory status and evidence requirements.

**FHIR alignment:** `health:MedicationRecord` aligns with `fhir:MedicationStatement`. The clinical ontology class `clinical:Medication` is defined as a subclass of both `fhir:MedicationStatement` and `prov:Entity`.

### 2.2 Properties Table -- MedicationRecord

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Medication Name | `health:medicationName` | `xsd:string` | MUST (1) | Name of the medication (e.g., "Metformin") |
| Is Active | `health:isActive` | `xsd:boolean` | MUST (1) | Whether patient is currently taking this medication |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated (see Section 1.6) |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version (format: "major.minor", e.g., "1.3") |
| Dose | `health:dose` | `xsd:string` | MAY (0..1) | Dosage information (e.g., "500mg") |
| Frequency | `health:frequency` | `xsd:string` | MAY (0..1) | How often taken (e.g., "twice daily") |
| Route | `health:route` | `xsd:string` | MAY (0..1) | Route of administration (e.g., "oral") |
| Prescriber | `health:prescriber` | `xsd:string` | MAY (0..1) | Name of prescribing physician |
| Start Date | `health:startDate` | `xsd:dateTime` | MAY (0..1) | When medication was started |
| End Date | `health:endDate` | `xsd:dateTime` | MAY (0..1) | When medication was stopped |
| RxNorm Code | `health:rxNormCode` | (URI) | MAY (0..1) | RxNorm concept URI (e.g., `rxnorm:860975`) |
| Notes | `health:notes` | `xsd:string` | MAY (0..1) | Free-text notes |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source system |
| Drug Code | `clinical:drugCode` | (URI) | MAY (0..*) | Drug code URI from any terminology system |
| Provenance Class | `clinical:provenanceClass` | `xsd:string` | MUST (1) | Editability class: `healthKitFHIR`, `userTracked`, `pharmacyClaim`, `imported` |
| Source FHIR Type | `clinical:sourceFhirResourceType` | `xsd:string` | MAY (0..1) | FHIR resource type: `MedicationRequest`, `MedicationStatement`, `MedicationDispense`, `MedicationAdministration` |
| Clinical Intent | `clinical:clinicalIntent` | `xsd:string` | MAY (0..1) | Intent: `reportedUse`, `prescribed`, `dispensed`, `administered` |
| Indication | `clinical:indication` | `xsd:string` | MAY (0..1) | Clinical reason for the medication |
| Course of Therapy | `clinical:courseOfTherapyType` | `xsd:string` | MAY (0..1) | `acute`, `continuous`, or `unknown` |
| As Needed (PRN) | `clinical:asNeeded` | `xsd:boolean` | MAY (0..1) | Whether taken as needed |
| Medication Form | `clinical:medicationForm` | `xsd:string` | MAY (0..1) | Physical form: tablet, capsule, liquid, etc. |
| Active Ingredient | `clinical:activeIngredient` | `xsd:string` | MAY (0..1) | Primary active ingredient name |
| Ingredient Strength | `clinical:ingredientStrength` | `xsd:string` | MAY (0..1) | Strength (e.g., "5 mg per tablet") |
| Refills Allowed | `clinical:refillsAllowed` | `xsd:integer` | MAY (0..1) | Number of authorized refills |
| Supply Duration | `clinical:supplyDurationDays` | `xsd:integer` | MAY (0..1) | Days each fill is intended to supply |
| Dispensed Quantity | `clinical:dispensedQuantity` | `xsd:string` | MAY (0..1) | Quantity per fill (e.g., "90 tablets") |
| Prescription Category | `clinical:prescriptionCategory` | `xsd:string` | MAY (0..1) | Context: `community`, `inpatient`, `discharge` |
| Medication Class | `health:medicationClass` | `xsd:string` | MAY (0..1) | Therapeutic classification (computed by ClinicalClassifier) |
| Affects Vital Signs | `health:affectsVitalSigns` | (List) | MAY (0..1) | Vital signs affected by this medication |

### 2.3 Turtle Example -- MedicationRecord (Annotated)

```turtle
@prefix health:   <https://ns.cascadeprotocol.org/health/v1#> .
@prefix clinical: <https://ns.cascadeprotocol.org/clinical/v1#> .
@prefix cascade:  <https://ns.cascadeprotocol.org/core/v1#> .
@prefix rxnorm:   <http://www.nlm.nih.gov/research/umls/rxnorm/> .
@prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .

# A medication record for Metformin imported from Epic MyChart
<urn:uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890> a health:MedicationRecord ;

    # --- Required fields ---
    health:medicationName "Metformin HCl" ;           # Drug name as recorded in EHR
    health:isActive true ;                             # Patient is currently taking this
    cascade:dataProvenance cascade:EHRVerified ;       # Imported from verified EHR system
    cascade:schemaVersion "1.3" ;                      # Schema version for compatibility

    # --- Core medication details ---
    health:dose "1000mg" ;                             # Prescribed dosage
    health:frequency "twice daily" ;                   # How often taken
    health:route "oral" ;                              # Route of administration
    health:prescriber "Dr. Sarah Chen" ;               # Prescribing physician
    health:startDate "2024-01-15T00:00:00Z"^^xsd:dateTime ;  # When started
    health:notes "Take with meals" ;                   # Patient instructions

    # --- Standard coding (RxNorm URI) ---
    health:rxNormCode <rxnorm:860975> ;                # RxNorm concept for Metformin 1000mg

    # --- Multi-system drug codes ---
    clinical:drugCode <http://www.nlm.nih.gov/research/umls/rxnorm/860975> ;  # RxNorm
    clinical:drugCode <http://snomed.info/sct/109081006> ;                     # SNOMED CT

    # --- Provenance and source tracking ---
    clinical:provenanceClass "healthKitFHIR" ;         # Read-only EHR import (not editable)
    clinical:sourceFhirResourceType "MedicationRequest" ;  # Originated from a prescription
    clinical:clinicalIntent "prescribed" ;             # Provider ordered this medication
    health:sourceRecordId "epic-med-12345" ;           # FHIR resource ID for traceability

    # --- FHIR-enriched medication details ---
    clinical:indication "Type 2 Diabetes Mellitus" ;   # Clinical reason for prescribing
    clinical:courseOfTherapyType "continuous" ;         # Ongoing therapy (not short-course)
    clinical:asNeeded false ;                          # Fixed schedule, not PRN
    clinical:medicationForm "tablet" ;                 # Physical form
    clinical:activeIngredient "metformin hydrochloride" ;  # Active ingredient
    clinical:ingredientStrength "1000 mg per tablet" ; # Strength per unit

    # --- Dispensing details ---
    clinical:refillsAllowed 5 ;                        # 5 refills authorized
    clinical:supplyDurationDays 90 ;                   # 90-day supply per fill
    clinical:dispensedQuantity "180 tablets" ;          # Quantity per fill
    clinical:prescriptionCategory "community" ;        # Community/outpatient prescription

    # --- Classification metadata (computed) ---
    health:medicationClass "antidiabetic" ;            # Therapeutic class
    health:affectsVitalSigns ("bloodGlucose") .        # Affects blood glucose
```

### 2.4 JSON-LD Equivalent -- MedicationRecord

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "@type": "health:MedicationRecord",
  "health:medicationName": "Metformin HCl",
  "health:isActive": true,
  "cascade:dataProvenance": { "@id": "cascade:EHRVerified" },
  "cascade:schemaVersion": "1.3",
  "health:dose": "1000mg",
  "health:frequency": "twice daily",
  "health:route": "oral",
  "health:prescriber": "Dr. Sarah Chen",
  "health:startDate": {
    "@value": "2024-01-15T00:00:00Z",
    "@type": "xsd:dateTime"
  },
  "health:rxNormCode": { "@id": "rxnorm:860975" },
  "clinical:provenanceClass": "healthKitFHIR",
  "clinical:sourceFhirResourceType": "MedicationRequest",
  "clinical:clinicalIntent": "prescribed",
  "clinical:indication": "Type 2 Diabetes Mellitus",
  "clinical:courseOfTherapyType": "continuous",
  "clinical:asNeeded": false,
  "clinical:medicationForm": "tablet",
  "clinical:activeIngredient": "metformin hydrochloride",
  "clinical:ingredientStrength": "1000 mg per tablet",
  "clinical:refillsAllowed": 5,
  "clinical:supplyDurationDays": 90,
  "clinical:dispensedQuantity": "180 tablets",
  "clinical:prescriptionCategory": "community"
}
```

> **Note on `fhir:status` in JSON-LD:** The SDK's `JSONLDCodable.swift` module auto-injects `"fhir:status": "final"` when a resource has FHIR-aligned additional types (e.g., `fhir:MedicationStatement`). This injection affects JSON-LD output only, not Turtle. Consumers of JSON-LD output SHOULD be aware that `fhir:status` may appear even when not explicitly serialized.

### 2.5 Provenance -- Medications

Medication records can originate from multiple sources. The `cascade:dataProvenance` value indicates the source, while `clinical:provenanceClass` controls editability:

| Source | `cascade:dataProvenance` | `clinical:provenanceClass` | Editable? |
|---|---|---|---|
| EHR import (HealthKit FHIR) | `cascade:EHRVerified` | `healthKitFHIR` | No |
| Patient manual entry | `cascade:SelfReported` | `userTracked` | Yes |
| Pharmacy/PBM claim | `cascade:ClinicalGenerated` | `pharmacyClaim` | No |
| Pod sync / file import | `cascade:ClinicalGenerated` | `imported` | No |

### 2.6 SHACL Constraints -- Medications

The `clinical:MedicationShape` in `clinical.shapes.ttl` enforces these constraints:

| Property | Constraint | Severity |
|---|---|---|
| `clinical:drugName` | `sh:minCount 1`, `sh:minLength 1`, `xsd:string` | Violation |
| `cascade:dataProvenance` | `sh:minCount 1`, `sh:in (cascade:ClinicalGenerated, cascade:EHRVerified, cascade:DeviceGenerated, cascade:PatientReported)` | Violation |
| `cascade:schemaVersion` | `sh:minCount 1`, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation |
| `clinical:courseOfTherapyType` | `sh:in ("acute", "continuous", "unknown")` | Warning |
| `clinical:provenanceClass` | `sh:in ("healthKitFHIR", "userTracked", "pharmacyClaim", "imported")` | (no severity) |
| `clinical:sourceFhirResourceType` | `sh:in ("MedicationRequest", "MedicationStatement", "MedicationDispense", "MedicationAdministration")` | (no severity) |
| `clinical:clinicalIntent` | `sh:in ("reportedUse", "prescribed", "dispensed", "administered")` | (no severity) |
| `clinical:prescriptionCategory` | `sh:in ("community", "inpatient", "discharge")` | (no severity) |
| `clinical:refillsAllowed` | `sh:minInclusive 0`, `xsd:integer` | (no severity) |

> **Note on type discrepancy:** The SHACL shape targets `clinical:Medication` and requires `clinical:drugName`, while the reference SDK serializer types the resource as `health:MedicationRecord` and uses `health:medicationName`. This reflects a planned migration from `health:` to `clinical:` namespace for clinical records. Implementers SHOULD follow the SDK serializer patterns shown in Section 2.3.

### 2.7 Multi-System Coding -- Medications

Medications support multiple coding systems for interoperability. The `clinical:drugCode` property accepts URIs from any of these systems:

| System | URI Pattern | Example |
|---|---|---|
| **RxNorm** | `http://www.nlm.nih.gov/research/umls/rxnorm/{code}` | `rxnorm:860975` (Metformin 1000mg) |
| **SNOMED CT** | `http://snomed.info/sct/{code}` | `sct:109081006` (Metformin) |
| **NDC** | `http://hl7.org/fhir/sid/ndc/{code}` | NDC package code |
| **ATC** | `http://www.whocc.no/atc/{code}` | ATC classification code |

The `health:rxNormCode` property provides a shorthand for the most common case (RxNorm), but `clinical:drugCode` is the general-purpose multi-system coding property. A medication record MAY include multiple `clinical:drugCode` triples from different systems.

### 2.8 Supplements

Supplements use the `clinical:Supplement` type with a distinct set of required fields emphasizing regulatory status:

```turtle
<urn:uuid:b2c3d4e5-f6a7-8901-bcde-f12345678901> a clinical:Supplement ;

    # --- Required fields ---
    clinical:supplementName "Vitamin D3" ;                     # Supplement name
    clinical:regulatoryStatus "dietarySupplement" ;            # REQUIRED: explicit regulatory class
    clinical:isActive true ;                                   # Currently taking
    cascade:dataProvenance cascade:SelfReported ;              # Patient-entered
    cascade:schemaVersion "1.3" ;                              # Schema version

    # --- Optional details ---
    clinical:dose "5000 IU" ;                                  # Dosage
    clinical:frequency "once daily" ;                          # Frequency
    clinical:brand "Nature Made" ;                             # Brand name
    clinical:form "softgel" ;                                  # Physical form
    clinical:evidenceStrength "strongEvidence" ;               # Evidence level
    clinical:startDate "2024-06-01T00:00:00Z"^^xsd:dateTime ; # Start date
    clinical:reasonForUse "Vitamin D deficiency" ;             # Why taking it
    clinical:cascadeUri <https://ns.cascadeprotocol.org/supplements/vitamin-d3> .  # Stable ID
```

#### 2.8.1 Properties Table -- Supplements

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Supplement Name | `clinical:supplementName` | `xsd:string` | MUST (1) | Name of the supplement |
| Regulatory Status | `clinical:regulatoryStatus` | `xsd:string` | MUST (1) | Regulatory classification (see values below) |
| Is Active | `clinical:isActive` | `xsd:boolean` | MUST (1) | Currently taking |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Dose | `clinical:dose` | `xsd:string` | MAY (0..1) | Dosage amount and unit |
| Frequency | `clinical:frequency` | `xsd:string` | MAY (0..1) | How often taken |
| Brand | `clinical:brand` | `xsd:string` | MAY (0..1) | Brand name |
| Form | `clinical:form` | `xsd:string` | MAY (0..1) | Physical form: `capsule`, `tablet`, `softgel`, `liquid`, `powder`, `gummy`, `spray`, `patch`, `tea`, `tincture`, `other` |
| Evidence Strength | `clinical:evidenceStrength` | `xsd:string` | MAY (0..1) | Level of clinical evidence (see values below) |
| Start Date | `clinical:startDate` | `xsd:dateTime` | MAY (0..1) | When the patient started taking |
| Reason for Use | `clinical:reasonForUse` | `xsd:string` | MAY (0..1) | Why the patient is taking it |
| Cascade URI | `clinical:cascadeUri` | (URI) | MAY (0..1) | Stable Cascade identifier URI |

**`regulatoryStatus` valid values:** `dietarySupplement`, `otcDrug`, `homeopathic`, `herbalRemedy`, `unknown`. This property is REQUIRED (`sh:Violation`) to prevent implying clinical equivalence with prescription medications.

**`evidenceStrength` valid values:** `strongEvidence`, `moderateEvidence`, `limitedEvidence`, `traditionalUse`, `noEvidence`, `unknown`. This classifies the level of clinical evidence supporting the supplement's use for the stated reason.

#### 2.8.2 JSON-LD Equivalent -- Supplements

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "@type": "clinical:Supplement",
  "clinical:supplementName": "Vitamin D3",
  "clinical:regulatoryStatus": "dietarySupplement",
  "clinical:isActive": true,
  "cascade:dataProvenance": { "@id": "cascade:SelfReported" },
  "cascade:schemaVersion": "1.3",
  "clinical:dose": "5000 IU",
  "clinical:frequency": "once daily",
  "clinical:brand": "Nature Made",
  "clinical:form": "softgel",
  "clinical:evidenceStrength": "strongEvidence",
  "clinical:startDate": {
    "@value": "2024-06-01T00:00:00Z",
    "@type": "xsd:dateTime"
  },
  "clinical:reasonForUse": "Vitamin D deficiency"
}
```

---

## 3. Conditions

### 3.1 Description

Conditions represent medical conditions, diagnoses, and health problems. They are imported from EHR systems (via FHIR `Condition` resources) or manually entered by patients. Conditions are relatively simple categorical data -- they do not require longitudinal episode tracking like medications.

**FHIR alignment:** `clinical:Condition` is defined as a subclass of both `fhir:Condition` and `prov:Entity` in the clinical ontology.

### 3.2 Properties Table

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Condition Name | `health:conditionName` | `xsd:string` | MUST (1) | Name of the condition (e.g., "Type 2 Diabetes Mellitus") |
| Status | `health:status` | `xsd:string` | MUST (1) | Condition status: `active`, `resolved`, `remission`, `recurrence`, `inactive` |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Onset Date | `health:onsetDate` | `xsd:dateTime` | MAY (0..1) | When the condition began |
| Abatement Date | `health:abatementDate` | `xsd:dateTime` | MAY (0..1) | When the condition resolved |
| ICD-10 Code | `health:icd10Code` | (URI) | MAY (0..1) | ICD-10-CM diagnosis code URI |
| SNOMED Code | `health:snomedCode` | (URI) | MAY (0..1) | SNOMED CT concept URI |
| Notes | `health:notes` | `xsd:string` | MAY (0..1) | Free-text notes |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source system |
| Condition Class | `health:conditionClass` | `xsd:string` | MAY (0..1) | Classification (computed by ClinicalClassifier) |
| Monitored Vital Signs | `health:monitoredVitalSigns` | (List) | MAY (0..1) | Vital signs to monitor for this condition |

### 3.3 Turtle Example (Annotated)

```turtle
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix sct:     <http://snomed.info/sct/> .
@prefix icd10:   <http://hl7.org/fhir/sid/icd-10-cm/> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .

# A condition record for essential hypertension from EHR
<urn:uuid:c3d4e5f6-a7b8-9012-cdef-123456789012> a health:ConditionRecord ;

    # --- Required fields ---
    health:conditionName "Essential Hypertension" ;        # Condition name from EHR
    health:status "active" ;                               # Currently active condition
    cascade:dataProvenance cascade:EHRVerified ;           # Imported from EHR
    cascade:schemaVersion "1.3" ;                          # Schema version

    # --- Clinical dates ---
    health:onsetDate "2022-06-15T00:00:00Z"^^xsd:dateTime ;  # When diagnosed

    # --- Standard coding ---
    health:icd10Code <icd10:I10> ;                         # ICD-10 code for essential HTN
    health:snomedCode <sct:59621000> ;                     # SNOMED CT: Essential hypertension

    # --- Source tracking ---
    health:sourceRecordId "epic-cond-67890" ;              # FHIR Condition resource ID

    # --- Classification metadata (computed) ---
    health:conditionClass "cardiovascular" ;               # Therapeutic class
    health:monitoredVitalSigns ("bloodPressure" "heartRate") .  # Vitals to monitor
```

### 3.4 JSON-LD Equivalent

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:c3d4e5f6-a7b8-9012-cdef-123456789012",
  "@type": "health:ConditionRecord",
  "health:conditionName": "Essential Hypertension",
  "health:status": "active",
  "cascade:dataProvenance": { "@id": "cascade:EHRVerified" },
  "cascade:schemaVersion": "1.3",
  "health:onsetDate": {
    "@value": "2022-06-15T00:00:00Z",
    "@type": "xsd:dateTime"
  },
  "health:icd10Code": { "@id": "icd10:I10" },
  "health:snomedCode": { "@id": "sct:59621000" },
  "health:sourceRecordId": "epic-cond-67890"
}
```

### 3.5 Provenance -- Conditions

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| EHR import | `cascade:EHRVerified` | Conditions from Epic MyChart, Cerner |
| Patient entry | `cascade:SelfReported` | Self-reported conditions |
| AI extraction | `cascade:AIExtracted` | Conditions extracted from clinical notes |

### 3.6 SHACL Constraints -- Conditions

The `clinical:ConditionShape` in `clinical.shapes.ttl` enforces:

| Property | Constraint | Severity |
|---|---|---|
| `clinical:conditionName` | `sh:minCount 1`, `sh:minLength 1`, `xsd:string` | Violation |
| `cascade:dataProvenance` | `sh:minCount 1`, valid provenance class | Violation |
| `cascade:schemaVersion` | `sh:minCount 1`, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation |
| `clinical:clinicalStatus` | `sh:in ("active", "recurrence", "relapse", "inactive", "remission", "resolved")` | (no severity) |
| `clinical:verificationStatus` | `sh:in ("unconfirmed", "provisional", "differential", "confirmed", "refuted", "entered-in-error")` | (no severity) |
| `clinical:onsetDate` | `xsd:dateTime`, `sh:maxCount 1` | (no severity) |

> **Note on type discrepancy:** The SHACL shape targets `clinical:Condition` and requires `clinical:conditionName`, while the reference SDK serializer types the resource as `health:ConditionRecord` and uses `health:conditionName`. This mirrors the medication namespace migration (see Section 2.6). Implementers SHOULD follow the SDK serializer patterns shown in Section 3.3.

### 3.7 Multi-System Coding -- Conditions

Conditions support two primary coding systems:

| System | URI Pattern | Example |
|---|---|---|
| **ICD-10-CM** | `http://hl7.org/fhir/sid/icd-10-cm/{code}` | `icd10:I10` (Essential hypertension) |
| **SNOMED CT** | `http://snomed.info/sct/{code}` | `sct:59621000` (Essential hypertension) |

Both codes are emitted as URI references (not string literals) in Turtle to enable linked-data traversal. A condition record MAY include codes from both systems.

---

## 4. Allergies

### 4.1 Description

Allergies represent allergic reactions and intolerances to substances including medications, foods, environmental factors, and biologics. They are imported from EHR systems (via FHIR `AllergyIntolerance` resources) or manually entered by patients.

**FHIR alignment:** `clinical:Allergy` is defined as a subclass of both `fhir:AllergyIntolerance` and `prov:Entity`.

### 4.2 Properties Table

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Allergen | `health:allergen` | `xsd:string` | MUST (1) | Name of the allergen or substance |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Category | `health:allergyCategory` | `xsd:string` | MAY (0..1) | Category: `medication`, `food`, `environmental`, `latex`, `contrast`, `insect`, `other` |
| Reaction | `health:reaction` | `xsd:string` | MAY (0..1) | Description of allergic reaction |
| Severity | `health:allergySeverity` | `xsd:string` | MAY (0..1) | `mild`, `moderate`, `severe`, `life_threatening` |
| Onset Date | `health:onsetDate` | `xsd:dateTime` | MAY (0..1) | When the allergy was first identified |
| Notes | `health:notes` | `xsd:string` | MAY (0..1) | Free-text notes |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source system |

### 4.3 Turtle Example (Annotated)

```turtle
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .

# An allergy record for penicillin from EHR
<urn:uuid:d4e5f6a7-b8c9-0123-defa-234567890123> a health:AllergyRecord ;

    # --- Required fields ---
    health:allergen "Penicillin" ;                          # Substance causing allergy
    cascade:dataProvenance cascade:EHRVerified ;            # Imported from EHR
    cascade:schemaVersion "1.3" ;                           # Schema version

    # --- Clinical details ---
    health:allergyCategory "medication" ;                   # Category of allergen
    health:reaction "Hives, difficulty breathing" ;         # Observed reaction
    health:allergySeverity "severe" ;                       # Severity classification
    health:onsetDate "2015-03-20T00:00:00Z"^^xsd:dateTime ;  # When first identified

    # --- Source tracking ---
    health:sourceRecordId "epic-allergy-54321" .           # FHIR AllergyIntolerance ID
```

### 4.4 JSON-LD Equivalent

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:d4e5f6a7-b8c9-0123-defa-234567890123",
  "@type": "health:AllergyRecord",
  "health:allergen": "Penicillin",
  "cascade:dataProvenance": { "@id": "cascade:EHRVerified" },
  "cascade:schemaVersion": "1.3",
  "health:allergyCategory": "medication",
  "health:reaction": "Hives, difficulty breathing",
  "health:allergySeverity": "severe",
  "health:onsetDate": {
    "@value": "2015-03-20T00:00:00Z",
    "@type": "xsd:dateTime"
  },
  "health:sourceRecordId": "epic-allergy-54321"
}
```

### 4.5 Provenance -- Allergies

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| EHR import | `cascade:EHRVerified` | Allergies documented in medical record |
| Patient entry | `cascade:SelfReported` | Self-reported allergies |
| Provider report | `cascade:ClinicalGenerated` | Documented during clinical encounter |

### 4.6 SHACL Constraints -- Allergies

The `clinical:AllergyShape` in `clinical.shapes.ttl` enforces:

| Property | Constraint | Severity |
|---|---|---|
| `clinical:allergen` | `sh:minCount 1`, `sh:minLength 1`, `xsd:string` | Violation |
| `cascade:dataProvenance` | `sh:minCount 1`, valid provenance class | Violation |
| `cascade:schemaVersion` | `sh:minCount 1`, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation |
| `clinical:severity` | `sh:in ("mild", "moderate", "severe")` | (no severity) |
| `clinical:criticality` | `sh:in ("low", "high", "unable-to-assess")` | (no severity) |
| `clinical:category` | `sh:in ("food", "medication", "environment", "biologic")` | (no severity) |

> **Note on category values:** The SHACL shape uses FHIR `AllergyIntolerance.category` values (`food`, `medication`, `environment`, `biologic`), while the SDK `AllergyCategoryType` enum includes additional values (`latex`, `contrast`, `insect`, `other`). The SHACL constraint uses `sh:in` without a severity level, meaning extended values are accepted but may trigger informational messages.

> **Note on type discrepancy:** The SHACL shape targets `clinical:Allergy` and requires `clinical:allergen`, while the reference SDK serializer types the resource as `health:AllergyRecord` and uses `health:allergen`. This mirrors the medication namespace migration (see Section 2.6). Implementers SHOULD follow the SDK serializer patterns shown in Section 4.3.

### 4.7 Multi-System Coding -- Allergies

Allergy records MAY include a SNOMED CT code for the allergen substance:

| System | URI Pattern | Example |
|---|---|---|
| **SNOMED CT** | `http://snomed.info/sct/{code}` | `sct:91936005` (Allergy to penicillin) |

The SHACL shape allows `clinical:snomedCode` as either a string literal or a URI reference.

---

## 5. Lab Results

### 5.1 Description

Lab results represent individual laboratory test observations with a result value, unit, reference range, and interpretation. They are typically imported from EHR systems via FHIR `Observation` resources. Multiple lab results for the same test over time can be aggregated into a `clinical:LabTestSeries` for longitudinal tracking (Phase 2 scope).

**FHIR alignment:** `clinical:LabResult` is defined as a subclass of both `fhir:Observation` and `prov:Entity`.

### 5.2 Properties Table

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Test Name | `health:testName` | `xsd:string` | MUST (1) | Name of the laboratory test |
| Result Value | `health:resultValue` | `xsd:string` | MUST (1) | Numeric or string result |
| Interpretation | `health:interpretation` | `xsd:string` | MUST (1) | `normal`, `abnormal`, `critical`, `unknown` |
| Performed Date | `health:performedDate` | `xsd:dateTime` | MUST (1) | When the test was performed |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Test Code | `health:testCode` | (URI) | MAY (0..1) | LOINC code URI for the test |
| Category | `health:labCategory` | `xsd:string` | MAY (0..1) | Lab category (hematology, metabolic, etc.) |
| Result Unit | `health:resultUnit` | `xsd:string` | MAY (0..1) | Unit of measurement (UCUM preferred) |
| Reference Range | `health:referenceRange` | `xsd:string` | MAY (0..1) | Normal reference range text |
| Specimen Type | `health:specimenType` | `xsd:string` | MAY (0..1) | Specimen type (blood, urine, etc.) |
| Reported Date | `health:reportedDate` | `xsd:dateTime` | MAY (0..1) | When result was reported/finalized |
| Ordering Provider | `health:orderingProvider` | `xsd:string` | MAY (0..1) | Clinician who ordered the test |
| Performing Lab | `health:performingLab` | `xsd:string` | MAY (0..1) | Laboratory that ran the test |
| Notes | `health:notes` | `xsd:string` | MAY (0..1) | Free-text notes |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source system |

### 5.3 Turtle Example (Annotated)

```turtle
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix loinc:   <http://loinc.org/rdf#> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .

# A lab result for Hemoglobin A1C from clinical laboratory
<urn:uuid:e5f6a7b8-c9d0-1234-efab-345678901234> a health:LabResultRecord ;

    # --- Required fields ---
    health:testName "Hemoglobin A1C" ;                          # Test name
    health:resultValue "6.8" ;                                  # Result as string
    health:interpretation "abnormal" ;                          # Outside normal range
    health:performedDate "2025-11-15T08:30:00Z"^^xsd:dateTime ; # When specimen was drawn
    cascade:dataProvenance cascade:EHRVerified ;                # From verified EHR
    cascade:schemaVersion "1.3" ;                               # Schema version

    # --- Standard coding ---
    health:testCode <http://loinc.org/rdf#4548-4> ;              # LOINC code for HbA1c

    # --- Result details ---
    health:labCategory "metabolic" ;                            # Lab category
    health:resultUnit "%" ;                                     # Percentage unit
    health:referenceRange "4.0-5.6 %" ;                         # Normal range text
    health:specimenType "blood" ;                               # Blood specimen

    # --- Reporting details ---
    health:reportedDate "2025-11-16T14:00:00Z"^^xsd:dateTime ;  # When result was finalized
    health:orderingProvider "Dr. Michael Torres" ;              # Ordering physician
    health:performingLab "Quest Diagnostics" ;                  # Lab that performed test

    # --- Source tracking ---
    health:sourceRecordId "epic-lab-98765" .                    # FHIR Observation ID
```

### 5.4 JSON-LD Equivalent

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:e5f6a7b8-c9d0-1234-efab-345678901234",
  "@type": "health:LabResultRecord",
  "health:testName": "Hemoglobin A1C",
  "health:resultValue": "6.8",
  "health:interpretation": "abnormal",
  "health:performedDate": {
    "@value": "2025-11-15T08:30:00Z",
    "@type": "xsd:dateTime"
  },
  "cascade:dataProvenance": { "@id": "cascade:EHRVerified" },
  "cascade:schemaVersion": "1.3",
  "health:testCode": { "@id": "http://loinc.org/rdf#4548-4" },
  "health:labCategory": "metabolic",
  "health:resultUnit": "%",
  "health:referenceRange": "4.0-5.6 %",
  "health:specimenType": "blood",
  "health:orderingProvider": "Dr. Michael Torres",
  "health:performingLab": "Quest Diagnostics"
}
```

### 5.5 Provenance -- Lab Results

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| EHR import | `cascade:EHRVerified` | Lab results from hospital/clinic EHR |
| Patient entry | `cascade:SelfReported` | Self-reported lab values (e.g., home A1C test) |
| Device | `cascade:DeviceGenerated` | Point-of-care device readings |

### 5.6 SHACL Constraints -- Lab Results

The `clinical:LabResultShape` in `clinical.shapes.ttl` enforces:

| Property | Constraint | Severity |
|---|---|---|
| `clinical:testName` | `sh:minCount 1`, `sh:minLength 1`, `xsd:string` | Violation |
| `cascade:dataProvenance` | `sh:minCount 1`, valid provenance class | Violation |
| `cascade:schemaVersion` | `sh:minCount 1`, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation |
| `clinical:interpretation` | `sh:in ("normal", "high", "low", "abnormal", "critical", "Normal", "High", "Low", "Abnormal", "Critical")` | (no severity) |
| `clinical:value` | `sh:maxCount 1` | (no severity) |
| `clinical:unit` | `xsd:string`, `sh:maxCount 1` | (no severity) |

> **Note on type discrepancy:** The SHACL shape targets `clinical:LabResult` and requires `clinical:testName`, while the reference SDK serializer types the resource as `health:LabResultRecord` and uses `health:testName`. This mirrors the medication namespace migration (see Section 2.6). Implementers SHOULD follow the SDK serializer patterns shown in Section 5.3.

### 5.7 Multi-System Coding -- Lab Results

Lab results use LOINC as the primary coding system:

| System | URI Pattern | Example |
|---|---|---|
| **LOINC** | `http://loinc.org/rdf#{code}` | `loinc:4548-4` (Hemoglobin A1C) |

The `health:testCode` predicate links to the LOINC URI for the test. See **Appendix B** for a reference table of common LOINC codes used in Cascade Protocol.

> **URI construction note:** The canonical LOINC namespace is `http://loinc.org/rdf#`, so `loinc:4548-4` expands to `http://loinc.org/rdf#4548-4`. Historical SDK versions may emit `http://loinc.org/{code}` (without `rdf#`). Consumers SHOULD accept both forms for backward compatibility, but new implementations MUST use the canonical `http://loinc.org/rdf#` form.

---

## 6. Vital Signs (Clinical)

### 6.1 Description

Clinical vital signs represent observations taken in a clinical setting (e.g., at a doctor's office, hospital, or clinic). These are distinct from device-measured wellness vitals in `HealthProfile` (see Phase 2) -- clinical vitals carry `cascade:ClinicalGenerated` provenance and include LOINC and SNOMED CT codes for each observation type.

**FHIR alignment:** `clinical:VitalSign` is defined as a subclass of both `fhir:Observation` and `prov:Entity`.

### 6.2 Properties Table

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Vital Type | `clinical:vitalType` | `xsd:string` | MUST (1) | Type code (e.g., `bloodPressureSystolic`, `heartRate`) |
| Vital Type Name | `clinical:vitalTypeName` | `xsd:string` | SHOULD (1) | Human-readable name (e.g., "Systolic Blood Pressure") |
| Value | `clinical:value` | `xsd:double` | MUST (1) | Numeric observation value |
| Unit | `clinical:unit` | `xsd:string` | MUST (1) | Unit of measurement (e.g., "mmHg", "bpm") |
| Effective Date | `clinical:effectiveDate` | `xsd:dateTime` | MUST (1) | When measurement was taken |
| LOINC Code | `clinical:loincCode` | (URI) | MUST (1) | LOINC observation code URI |
| SNOMED Code | `clinical:snomedCode` | (URI) | MUST (1) | SNOMED CT concept URI |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Reference Range Low | `clinical:referenceRangeLow` | `xsd:decimal` | MAY (0..1) | Lower bound of normal range |
| Reference Range High | `clinical:referenceRangeHigh` | `xsd:decimal` | MAY (0..1) | Upper bound of normal range |
| Interpretation | `clinical:interpretation` | `xsd:string` | MAY (0..1) | Interpretation (normal, high, low, etc.) |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source |
| Component Vital Type | `clinical:componentVitalType` | `xsd:string` | MAY (0..1) | For multi-component vitals (e.g., BP systolic/diastolic) |

### 6.3 Turtle Example (Annotated)

```turtle
@prefix clinical: <https://ns.cascadeprotocol.org/clinical/v1#> .
@prefix health:   <https://ns.cascadeprotocol.org/health/v1#> .
@prefix cascade:  <https://ns.cascadeprotocol.org/core/v1#> .
@prefix sct:      <http://snomed.info/sct/> .
@prefix loinc:    <http://loinc.org/rdf#> .
@prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .

# A systolic blood pressure reading from a clinical encounter
<urn:uuid:f6a7b8c9-d0e1-2345-fabc-456789012345> a clinical:VitalSign ;

    # --- Required fields ---
    clinical:vitalType "bloodPressureSystolic" ;                       # Vital type code
    clinical:vitalTypeName "Systolic Blood Pressure" ;                 # Human-readable name
    clinical:value 138.0 ;                                             # Numeric value
    clinical:unit "mmHg" ;                                             # Unit of measurement
    clinical:effectiveDate "2025-12-01T10:30:00Z"^^xsd:dateTime ;     # When measured
    clinical:loincCode <http://loinc.org/rdf#8480-6> ;                  # LOINC: Systolic BP
    clinical:snomedCode <sct:271649006> ;                              # SNOMED: Systolic BP
    cascade:dataProvenance cascade:EHRVerified ;                       # Clinical measurement
    cascade:schemaVersion "1.3" ;                                      # Schema version

    # --- Reference range ---
    clinical:referenceRangeLow 90.0 ;                                  # Normal lower bound
    clinical:referenceRangeHigh 120.0 ;                                # Normal upper bound
    clinical:interpretation "high" ;                                   # Above normal range

    # --- Source tracking ---
    health:sourceRecordId "epic-vital-11111" .                         # FHIR Observation ID
```

### 6.4 JSON-LD Equivalent

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:f6a7b8c9-d0e1-2345-fabc-456789012345",
  "@type": "clinical:VitalSign",
  "clinical:vitalType": "bloodPressureSystolic",
  "clinical:vitalTypeName": "Systolic Blood Pressure",
  "clinical:value": 138.0,
  "clinical:unit": "mmHg",
  "clinical:effectiveDate": {
    "@value": "2025-12-01T10:30:00Z",
    "@type": "xsd:dateTime"
  },
  "clinical:loincCode": { "@id": "http://loinc.org/rdf#8480-6" },
  "clinical:snomedCode": { "@id": "sct:271649006" },
  "cascade:dataProvenance": { "@id": "cascade:EHRVerified" },
  "cascade:schemaVersion": "1.3",
  "clinical:referenceRangeLow": 90.0,
  "clinical:referenceRangeHigh": 120.0,
  "clinical:interpretation": "high"
}
```

### 6.5 Provenance -- Vital Signs

Clinical vital signs are primarily EHR-sourced:

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| EHR import | `cascade:EHRVerified` | Vitals recorded during clinical encounters |
| Device in clinical setting | `cascade:ClinicalGenerated` | Medical-grade device in clinic |
| Patient-reported | `cascade:SelfReported` | Home BP readings entered manually |

### 6.6 SHACL Constraints -- Vital Signs

The `clinical:VitalSignShape` in `clinical.shapes.ttl` enforces:

| Property | Constraint | Severity |
|---|---|---|
| `clinical:vitalType` | `sh:minCount 1`, `sh:in` (see list below) | Violation |
| `cascade:dataProvenance` | `sh:minCount 1`, valid provenance class | Violation |
| `cascade:schemaVersion` | `sh:minCount 1`, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation |
| `clinical:value` | `sh:maxCount 1` | (no severity) |
| `clinical:unit` | `xsd:string`, `sh:maxCount 1` | (no severity) |
| `clinical:interpretation` | `xsd:string`, `sh:maxCount 1` | (no severity) |

**Valid `vitalType` values:** The SHACL shape accepts both code-style and display-style values:
- Code style: `heart_rate`, `blood_pressure`, `respiratory_rate`, `body_temperature`, `oxygen_saturation`, `body_weight`, `body_height`, `bmi`
- Display style: `Heart Rate`, `Blood Pressure`, `Respiratory Rate`, `Body Temperature`, `Oxygen Saturation`, `Body Weight`, `Body Height`, `BMI`

### 6.7 Multi-System Coding -- Vital Signs

Each vital sign type has both a LOINC observation code and a SNOMED CT concept code. The SDK's `ClinicalVitalType` enum provides these mappings:

| Vital Type | LOINC Code | SNOMED CT Code | Unit |
|---|---|---|---|
| Systolic Blood Pressure | `8480-6` | `271649006` | mmHg |
| Diastolic Blood Pressure | `8462-4` | `271650006` | mmHg |
| Heart Rate | `8867-4` | `364075005` | bpm |
| Respiratory Rate | `9279-1` | `86290005` | breaths/min |
| Body Temperature | `8310-5` | `386725007` | degC |
| Oxygen Saturation (SpO2) | `2708-6` | `431314004` | % |
| Body Weight | `29463-7` | `27113001` | kg |
| Body Height | `8302-2` | `50373000` | cm |
| BMI | `39156-5` | `60621009` | kg/m2 |

Both codes are emitted as URI references in the serialized output. For LOINC: `<http://loinc.org/rdf#{code}>`. For SNOMED CT: `<http://snomed.info/sct/{code}>`.

---

## 7. Patient Profile

### 7.1 Description

The Patient Profile represents health-specific patient demographics and identity extensions. It is designed to complement a Solid-compatible `foaf:Agent` identity profile using a two-document model:

- **`/profile/card.ttl`** -- General identity: `foaf:givenName`, `foaf:familyName`, `vcard:hasEmail`, `vcard:hasTelephone`, `dct:language`. May be shared with others.
- **`/profile/health.ttl`** -- Health demographics: `cascade:PatientProfile` with `cascade:dateOfBirth`, `cascade:biologicalSex`, etc. Always private.

The Patient Profile contains health-relevant demographic data that informs clinical calculations, screening eligibility, and care planning. It includes structured sub-resources for emergency contacts, addresses, pharmacy information, and advance directives.

**Storage path:** `/profile/health.ttl`

### 7.2 Properties Table

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Date of Birth | `cascade:dateOfBirth` | `xsd:date` | MUST (1) | Patient date of birth (format: YYYY-MM-DD) |
| Biological Sex | `cascade:biologicalSex` | `xsd:string` | MUST (1) | `male`, `female`, `intersex` |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Computed Age | `cascade:computedAge` | `xsd:integer` | SHOULD (1) | Age in years, computed at serialization time |
| Age Group | `cascade:ageGroup` | `xsd:string` | SHOULD (1) | `pediatric` (0-17), `young_adult` (18-39), `adult` (40-64), `senior` (65+) |
| Gender Identity | `cascade:genderIdentity` | `xsd:string` | SHOULD (0..1) | `woman`, `man`, `non_binary`, `other`, `prefer_not_to_say` |
| Emergency Contact | `cascade:emergencyContact` | (Blank node) | SHOULD (0..1) | Link to `cascade:EmergencyContact` |
| Address | `cascade:address` | (Blank node) | MAY (0..1) | Link to `cascade:Address` |
| Preferred Pharmacy | `cascade:preferredPharmacy` | (Blank node) | MAY (0..1) | Link to `cascade:PharmacyInfo` |
| Marital Status | `cascade:maritalStatus` | `xsd:string` | MAY (0..1) | `single`, `married`, `domestic_partnership`, `divorced`, `separated`, `widowed`, `prefer_not_to_say` |
| Race/Ethnicity | `cascade:raceEthnicity` | `xsd:string` | MAY (0..*) | Multi-value. See enumerated values below. |
| Advance Directives | `cascade:advanceDirectives` | (Blank node) | MAY (0..1) | Link to `cascade:AdvanceDirectives` |
| Profile ID | `cascade:profileId` | `xsd:string` | MAY (0..1) | UUID for traceability and deduplication |

**Race/Ethnicity values (OMB standard):** `american_indian_alaska_native`, `asian`, `black_african_american`, `hispanic_latino`, `native_hawaiian_pacific_islander`, `white`, `other`, `prefer_not_to_say`. Multiple values MAY be provided as separate triples with the same predicate.

### 7.3 Turtle Example (Annotated)

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:    <http://www.w3.org/ns/prov#> .

# Patient Profile stored at /profile/health.ttl
<#healthProfile> a cascade:PatientProfile ;

    # --- Required fields ---
    cascade:schemaVersion "2.0" ;                                  # Schema version
    cascade:dataProvenance cascade:SelfReported ;                  # Patient-entered data

    # --- Core demographics ---
    cascade:dateOfBirth "1985-03-15"^^xsd:date ;                   # Date of birth
    cascade:biologicalSex "female" ;                               # For clinical calculations

    # --- Computed convenience fields ---
    cascade:computedAge "40"^^xsd:integer ;                        # Computed at serialization
    cascade:ageGroup "adult" ;                                     # Derived from DOB

    # --- Optional demographics ---
    cascade:genderIdentity "woman" ;                               # Self-reported gender
    cascade:maritalStatus "married" ;                              # Marital status
    cascade:raceEthnicity "asian" ;                                # Multi-value (OMB)
    cascade:raceEthnicity "white" ;                                # Second race/ethnicity

    # --- Emergency contact (blank node) ---
    cascade:emergencyContact [
        a cascade:EmergencyContact ;                               # Typed blank node
        cascade:contactName "John Doe" ;                           # Contact name (REQUIRED)
        cascade:contactRelationship "spouse" ;                     # Relationship to patient
        cascade:contactPhone "555-0123"                            # Phone number (REQUIRED)
    ] ;

    # --- Address (blank node with FHIR-aligned properties) ---
    cascade:address [
        a cascade:Address ;                                        # Typed blank node
        cascade:addressUse "home" ;                                # Purpose: home, work, temp
        cascade:addressLine "123 Main Street" ;                    # Street address line 1
        cascade:addressLine "Apt 4B" ;                             # Street address line 2
        cascade:addressCity "Portland" ;                           # City
        cascade:addressState "OR" ;                                # State
        cascade:addressPostalCode "97201" ;                        # ZIP code
        cascade:addressCountry "US"                                # Country
    ] ;

    # --- Preferred pharmacy (blank node) ---
    cascade:preferredPharmacy [
        a cascade:PharmacyInfo ;                                   # Typed blank node
        cascade:pharmacyName "CVS Pharmacy #1234" ;                # Name (REQUIRED)
        cascade:pharmacyAddress "456 Oak Ave, Portland, OR 97201" ;  # Address as string
        cascade:pharmacyPhone "555-0456"                           # Phone number
    ] ;

    # --- Advance directives (blank node, elevated PHI) ---
    cascade:advanceDirectives [
        a cascade:AdvanceDirectives ;                              # Typed blank node
        cascade:hasLivingWill "true"^^xsd:boolean ;                # Living will on file
        cascade:hasPowerOfAttorney "true"^^xsd:boolean ;           # Healthcare POA on file
        cascade:hasDNR "false"^^xsd:boolean ;                      # No DNR order
        cascade:advanceDirectiveNotes "Living will updated 2024-01-15"  # Notes
    ] ;

    # --- Profile identity ---
    cascade:profileId "A1B2C3D4-E5F6-7890-ABCD-EF1234567890" .    # UUID for traceability
```

### 7.4 JSON-LD Equivalent

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "#healthProfile",
  "@type": "cascade:PatientProfile",
  "cascade:schemaVersion": "2.0",
  "cascade:dataProvenance": { "@id": "cascade:SelfReported" },
  "cascade:dateOfBirth": {
    "@value": "1985-03-15",
    "@type": "xsd:date"
  },
  "cascade:biologicalSex": "female",
  "cascade:computedAge": {
    "@value": "40",
    "@type": "xsd:integer"
  },
  "cascade:ageGroup": "adult",
  "cascade:genderIdentity": "woman",
  "cascade:maritalStatus": "married",
  "cascade:raceEthnicity": ["asian", "white"],
  "cascade:emergencyContact": {
    "@type": "cascade:EmergencyContact",
    "cascade:contactName": "John Doe",
    "cascade:contactRelationship": "spouse",
    "cascade:contactPhone": "555-0123"
  },
  "cascade:address": {
    "@type": "cascade:Address",
    "cascade:addressUse": "home",
    "cascade:addressLine": ["123 Main Street", "Apt 4B"],
    "cascade:addressCity": "Portland",
    "cascade:addressState": "OR",
    "cascade:addressPostalCode": "97201",
    "cascade:addressCountry": "US"
  },
  "cascade:preferredPharmacy": {
    "@type": "cascade:PharmacyInfo",
    "cascade:pharmacyName": "CVS Pharmacy #1234",
    "cascade:pharmacyAddress": "456 Oak Ave, Portland, OR 97201",
    "cascade:pharmacyPhone": "555-0456"
  },
  "cascade:advanceDirectives": {
    "@type": "cascade:AdvanceDirectives",
    "cascade:hasLivingWill": true,
    "cascade:hasPowerOfAttorney": true,
    "cascade:hasDNR": false,
    "cascade:advanceDirectiveNotes": "Living will updated 2024-01-15"
  },
  "cascade:profileId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
}
```

### 7.5 Provenance -- Patient Profile

Patient profiles are always patient-entered data:

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| Patient entry | `cascade:SelfReported` | Intake forms, manual demographic entry |
| EHR import | `cascade:EHRVerified` | Demographics pulled from EHR record |

### 7.6 SHACL Constraints -- Patient Profile

The `cascade:PatientProfileShape` in `core.shapes.ttl` enforces:

| Property | Constraint | Severity |
|---|---|---|
| `cascade:dateOfBirth` | `sh:minCount 1`, `xsd:date` | Violation |
| `cascade:biologicalSex` | `sh:minCount 1`, `sh:in ("male", "female", "intersex")` | Violation |
| `cascade:dataProvenance` | `sh:minCount 1` | Violation |
| `cascade:genderIdentity` | `sh:in ("woman", "man", "non_binary", "other", "prefer_not_to_say")` | Warning |
| `cascade:emergencyContact` | `sh:class cascade:EmergencyContact` | Warning |
| `cascade:ageGroup` | `sh:in ("pediatric", "young_adult", "adult", "senior")` | Info |
| `cascade:computedAge` | `xsd:integer`, `sh:minInclusive 0`, `sh:maxInclusive 150` | Info |
| `cascade:maritalStatus` | `sh:in ("single", "married", "domestic_partnership", ...)` | Info |
| `cascade:raceEthnicity` | `sh:in` (OMB values) | Info |

**Sub-resource shapes:**

**EmergencyContact** (`cascade:EmergencyContactShape`):
| Property | Constraint | Severity |
|---|---|---|
| `cascade:contactName` | `sh:minCount 1`, `sh:minLength 1` | Violation |
| `cascade:contactPhone` | `sh:minCount 1`, `sh:minLength 1` | Violation |
| `cascade:contactRelationship` | `sh:in ("spouse", "parent", "child", "sibling", "partner", "friend", "caregiver", "other")` | Warning |

**PharmacyInfo** (`cascade:PharmacyInfoShape`):
| Property | Constraint | Severity |
|---|---|---|
| `cascade:pharmacyName` | `sh:minCount 1`, `sh:minLength 1` | Violation |
| `cascade:pharmacyAddress` | `xsd:string` | Info |
| `cascade:pharmacyPhone` | `xsd:string` | Info |

**AdvanceDirectives** (`cascade:AdvanceDirectivesShape`):
| Property | Constraint | Severity |
|---|---|---|
| `cascade:hasLivingWill` | `sh:minCount 1`, `xsd:boolean` | Violation |
| `cascade:hasPowerOfAttorney` | `sh:minCount 1`, `xsd:boolean` | Violation |
| `cascade:hasDNR` | `sh:minCount 1`, `xsd:boolean` | Violation |
| `cascade:advanceDirectiveNotes` | `xsd:string` | Info |

### 7.7 Two-Document Profile Model

The Patient Profile follows the Solid WebID Profile pattern with two documents:

```
/profile/
    card.ttl          <-- General identity (foaf:Agent)
    health.ttl        <-- Health demographics (cascade:PatientProfile)
```

The documents are linked via `rdfs:seeAlso`:

```turtle
# In card.ttl:
<#me> a foaf:Agent ;
    foaf:givenName "Jane" ;
    foaf:familyName "Doe" ;
    rdfs:seeAlso <health.ttl> .

# In health.ttl:
<#healthProfile> a cascade:PatientProfile ;
    cascade:dateOfBirth "1985-03-15"^^xsd:date ;
    cascade:biologicalSex "female" .
```

This separation enables different access control policies: the general profile may be shared with care team members, while the health profile is always private.

---

## 8. Immunizations

### 8.1 Description

Immunizations represent vaccination events including the vaccine administered, dose details, manufacturer, lot number, and administration context. They are primarily imported from EHR systems via FHIR `Immunization` resources.

**FHIR alignment:** `clinical:Immunization` is defined as a subclass of both `fhir:Immunization` and `prov:Entity` in the clinical ontology. The SDK serializer types the resource as `health:ImmunizationRecord`.

### 8.2 Properties Table

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Vaccine Name | `health:vaccineName` | `xsd:string` | MUST (1) | Name of the vaccine (e.g., "COVID-19 mRNA Vaccine") |
| Administration Date | `health:administrationDate` | `xsd:dateTime` | MUST (1) | When the vaccine was administered |
| Status | `health:status` | `xsd:string` | MUST (1) | `completed`, `entered-in-error`, `not-done` |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated (see Section 1.6) |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Vaccine Code | `health:vaccineCode` | `xsd:string` | MAY (0..1) | CVX vaccine code (e.g., "CVX-308") |
| Manufacturer | `health:manufacturer` | `xsd:string` | MAY (0..1) | Vaccine manufacturer name |
| Lot Number | `health:lotNumber` | `xsd:string` | MAY (0..1) | Vaccine lot number for traceability |
| Dose Quantity | `health:doseQuantity` | `xsd:string` | MAY (0..1) | Dose volume (e.g., "0.5 mL") |
| Dose Number | `health:doseNumber` | `xsd:integer` | MAY (0..1) | Dose number in multi-dose series (e.g., 1, 2, 3) |
| Route | `health:route` | `xsd:string` | MAY (0..1) | Route of administration (e.g., "intramuscular") |
| Site | `health:site` | `xsd:string` | MAY (0..1) | Body site (e.g., "Left deltoid") |
| Expiration Date | `health:expirationDate` | `xsd:dateTime` | MAY (0..1) | Vaccine expiration date |
| Administering Provider | `health:administeringProvider` | `xsd:string` | MAY (0..1) | Name of provider who administered vaccine |
| Administering Location | `health:administeringLocation` | `xsd:string` | MAY (0..1) | Facility where vaccine was given |
| Notes | `health:notes` | `xsd:string` | MAY (0..1) | Free-text notes |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source system |

### 8.3 Turtle Example (Annotated)

```turtle
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .

# A COVID-19 vaccination record from EHR
<urn:uuid:1mmz-0001-aaaa-bbbb-ccccddddeeee> a health:ImmunizationRecord ;

    # --- Required fields ---
    health:vaccineName "COVID-19 mRNA Vaccine (Pfizer-BioNTech, 2024-2025 Formula)" ;
    health:administrationDate "2024-10-15T10:00:00Z"^^xsd:dateTime ;
    health:status "completed" ;                                # Vaccine was administered
    cascade:dataProvenance cascade:ClinicalGenerated ;         # From EHR import
    cascade:schemaVersion "1.3" ;                              # Schema version

    # --- Vaccine identification ---
    health:vaccineCode "CVX-308" ;                             # CVX code for this formulation
    health:manufacturer "Pfizer-BioNTech" ;                    # Manufacturer
    health:lotNumber "FN2487" ;                                # Lot number for recall tracing

    # --- Dose details ---
    health:doseQuantity "0.3 mL" ;                             # Volume administered
    health:route "intramuscular" ;                             # Route of administration
    health:site "Left deltoid" ;                               # Body site

    # --- Administration context ---
    health:administeringProvider "RN Maria Thompson" ;         # Administering nurse/provider
    health:administeringLocation "Cascade Primary Care" ;      # Facility name

    # --- Notes and source tracking ---
    health:notes "2024-2025 updated formulation. No adverse reactions observed during 15-min monitoring period." ;
    health:sourceRecordId "ehr-imm-2024-1015-001" .            # FHIR Immunization ID
```

### 8.4 JSON-LD Equivalent

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:1mmz-0001-aaaa-bbbb-ccccddddeeee",
  "@type": "health:ImmunizationRecord",
  "health:vaccineName": "COVID-19 mRNA Vaccine (Pfizer-BioNTech, 2024-2025 Formula)",
  "health:administrationDate": {
    "@value": "2024-10-15T10:00:00Z",
    "@type": "xsd:dateTime"
  },
  "health:status": "completed",
  "cascade:dataProvenance": { "@id": "cascade:ClinicalGenerated" },
  "cascade:schemaVersion": "1.3",
  "health:vaccineCode": "CVX-308",
  "health:manufacturer": "Pfizer-BioNTech",
  "health:lotNumber": "FN2487",
  "health:doseQuantity": "0.3 mL",
  "health:route": "intramuscular",
  "health:site": "Left deltoid",
  "health:administeringProvider": "RN Maria Thompson",
  "health:administeringLocation": "Cascade Primary Care",
  "health:sourceRecordId": "ehr-imm-2024-1015-001"
}
```

### 8.5 Provenance -- Immunizations

Immunization records are primarily clinical:

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| EHR import | `cascade:ClinicalGenerated` | Vaccinations from hospital/clinic EHR |
| EHR verified | `cascade:EHRVerified` | Verified immunization history from patient portal |
| Patient entry | `cascade:SelfReported` | Self-reported vaccinations (e.g., pharmacy walk-in) |

### 8.6 SHACL Constraints -- Immunizations

The `clinical:ImmunizationShape` in `clinical.shapes.ttl` enforces:

| Property | Constraint | Severity |
|---|---|---|
| `clinical:vaccineName` | `sh:minCount 1`, `sh:minLength 1`, `xsd:string` | Violation |
| `cascade:dataProvenance` | `sh:minCount 1`, valid provenance class | Violation |
| `cascade:schemaVersion` | `sh:minCount 1`, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation |
| `clinical:status` | `sh:in ("completed", "entered-in-error", "not-done")` | (no severity) |
| `clinical:cvxCode` | `sh:maxCount 1` | (no severity) |
| `clinical:lotNumber` | `xsd:string`, `sh:maxCount 1` | (no severity) |
| `clinical:site` | `xsd:string`, `sh:maxCount 1` | (no severity) |
| `clinical:doseQuantity` | `xsd:string`, `sh:maxCount 1` | (no severity) |
| `clinical:manufacturer` | `xsd:string`, `sh:maxCount 1` | (no severity) |

> **Note on type discrepancy:** The SHACL shape targets `clinical:Immunization` and requires `clinical:vaccineName`, while the reference SDK serializer types the resource as `health:ImmunizationRecord` and uses `health:vaccineName`. This mirrors the medication namespace migration (see Section 2.6). Implementers SHOULD follow the SDK serializer patterns shown in Section 8.3.

### 8.7 Multi-System Coding -- Immunizations

Immunizations use CVX (CDC Vaccine Codes) as the primary coding system:

| System | Format | Example |
|---|---|---|
| **CVX** | String code (e.g., "CVX-308") | CVX-308 (COVID-19 mRNA, bivalent) |
| **CVX** | String code (e.g., "CVX-197") | CVX-197 (Influenza, quadrivalent) |
| **CVX** | String code (e.g., "CVX-115") | CVX-115 (Tdap) |

The `health:vaccineCode` property stores the CVX code as a string literal. Unlike medications and conditions, immunization codes are not emitted as URI references because no canonical RDF namespace exists for CVX codes. Implementers MAY construct URIs using `http://hl7.org/fhir/sid/cvx/{code}` for linked-data interoperability.

---

## 9. Procedures

### 9.1 Description

Procedures represent clinical or surgical procedures performed on the patient. They are imported from EHR systems via FHIR `Procedure` resources and include information about the procedure type, date, performer, body site, and outcome.

**FHIR alignment:** `clinical:Procedure` is defined as a subclass of both `fhir:Procedure` and `prov:Entity`. The SDK serializer types the resource as `clinical:Procedure`.

### 9.2 Properties Table

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Procedure Name | `clinical:procedureName` | `xsd:string` | MUST (1) | Name of the procedure (e.g., "Colonoscopy") |
| Status | `clinical:status` | `xsd:string` | MUST (1) | Procedure status (see values below) |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Category | `clinical:category` | `xsd:string` | MAY (0..1) | Procedure category (e.g., "diagnostic", "surgical") |
| Performed Date | `clinical:performedDate` | `xsd:dateTime` | MAY (0..1) | When the procedure was performed |
| Body Site | `clinical:bodySite` | `xsd:string` | MAY (0..1) | Anatomical site (e.g., "Right knee") |
| Performer | `clinical:performer` | `xsd:string` | MAY (0..1) | Name of the performing clinician |
| Location | `clinical:location` | `xsd:string` | MAY (0..1) | Facility where procedure was performed |
| Outcome | `clinical:outcome` | `xsd:string` | MAY (0..1) | Procedure outcome description |
| CPT Code | `clinical:cptCode` | `xsd:string` | MAY (0..1) | CPT procedure code (5 digits) |
| SNOMED Code | `sct:code` | `xsd:string` | MAY (0..1) | SNOMED CT concept code |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source system |

**Valid `status` values:** `preparation`, `in-progress`, `not-done`, `on-hold`, `stopped`, `completed`, `entered-in-error`, `unknown`.

### 9.3 Turtle Example (Annotated)

```turtle
@prefix clinical: <https://ns.cascadeprotocol.org/clinical/v1#> .
@prefix health:   <https://ns.cascadeprotocol.org/health/v1#> .
@prefix cascade:  <https://ns.cascadeprotocol.org/core/v1#> .
@prefix sct:      <http://snomed.info/sct/> .
@prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .

# A colonoscopy procedure from EHR
<urn:uuid:a1b2c3d4-proc-5678-abcd-ef1234567890> a clinical:Procedure ;

    # --- Required fields ---
    clinical:procedureName "Colonoscopy" ;                                     # Procedure name
    clinical:status "completed" ;                                              # Successfully completed
    cascade:dataProvenance cascade:EHRVerified ;                               # Imported from EHR
    cascade:schemaVersion "1.3" ;                                              # Schema version

    # --- Procedure details ---
    clinical:category "diagnostic" ;                                           # Diagnostic procedure
    clinical:performedDate "2025-06-15T08:00:00Z"^^xsd:dateTime ;            # When performed
    clinical:bodySite "Colon" ;                                                # Anatomical site
    clinical:performer "Dr. James Wilson" ;                                    # Performing physician
    clinical:location "Cascade Surgical Center" ;                              # Facility

    # --- Outcome ---
    clinical:outcome "Normal findings. Two small polyps removed and sent to pathology." ;

    # --- Standard coding ---
    sct:code "73761001" ;                                                      # SNOMED CT: Colonoscopy
    clinical:cptCode "45378" ;                                                 # CPT: Diagnostic colonoscopy

    # --- Source tracking ---
    health:sourceRecordId "ehr-proc-20250615-001" .                           # FHIR Procedure ID
```

### 9.4 JSON-LD Equivalent

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:a1b2c3d4-proc-5678-abcd-ef1234567890",
  "@type": "clinical:Procedure",
  "clinical:procedureName": "Colonoscopy",
  "clinical:status": "completed",
  "cascade:dataProvenance": { "@id": "cascade:EHRVerified" },
  "cascade:schemaVersion": "1.3",
  "clinical:category": "diagnostic",
  "clinical:performedDate": {
    "@value": "2025-06-15T08:00:00Z",
    "@type": "xsd:dateTime"
  },
  "clinical:bodySite": "Colon",
  "clinical:performer": "Dr. James Wilson",
  "clinical:location": "Cascade Surgical Center",
  "clinical:outcome": "Normal findings. Two small polyps removed and sent to pathology.",
  "sct:code": "73761001",
  "clinical:cptCode": "45378",
  "health:sourceRecordId": "ehr-proc-20250615-001"
}
```

### 9.5 Provenance -- Procedures

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| EHR import | `cascade:EHRVerified` | Procedures documented in medical record |
| Clinical setting | `cascade:ClinicalGenerated` | Procedure records from clinical encounter |
| Patient entry | `cascade:SelfReported` | Self-reported procedures (e.g., outpatient visits) |

### 9.6 SHACL Constraints -- Procedures

The `clinical:ProcedureShape` in `clinical.shapes.ttl` enforces:

| Property | Constraint | Severity |
|---|---|---|
| `clinical:procedureName` | `sh:minCount 1`, `sh:minLength 1`, `xsd:string` | Violation |
| `cascade:dataProvenance` | `sh:minCount 1`, valid provenance class | Violation |
| `cascade:schemaVersion` | `sh:minCount 1`, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation |
| `clinical:status` | `sh:in ("preparation", "in-progress", "not-done", "on-hold", "stopped", "completed", "entered-in-error", "unknown")` | (no severity) |
| `clinical:cptCode` | `sh:pattern "^[0-9]{5}$"`, `sh:maxCount 1` | (no severity) |
| `clinical:snomedCode` | `sh:maxCount 1` | (no severity) |
| `clinical:bodySite` | `xsd:string`, `sh:maxCount 1` | (no severity) |
| `clinical:performer` | `xsd:string`, `sh:maxCount 1` | (no severity) |
| `clinical:performedDate` | `xsd:dateTime`, `sh:maxCount 1` | (no severity) |

### 9.7 Multi-System Coding -- Procedures

Procedures support two primary coding systems:

| System | URI Pattern / Format | Example |
|---|---|---|
| **CPT** | 5-digit string code | `45378` (Diagnostic colonoscopy) |
| **SNOMED CT** | String code via `sct:code` | `73761001` (Colonoscopy) |

The `clinical:cptCode` property stores CPT codes as 5-digit string literals (validated by SHACL pattern `^[0-9]{5}$`). SNOMED CT codes are emitted via `sct:code` as string literals in the current SDK serializer. Future versions MAY emit SNOMED codes as URI references.

---

## 10. Family History

### 10.1 Description

Family history records represent medical conditions in blood relatives that may have implications for the patient's health risk assessment. Each record captures a single condition-relationship pair (e.g., "Father had Type 2 Diabetes"). Family history is typically patient-reported or imported from structured EHR data.

**FHIR alignment:** Aligns with `fhir:FamilyMemberHistory`. The SDK serializer types the resource as `health:FamilyHistoryRecord`.

### 10.2 Properties Table

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Relationship | `health:relationship` | `xsd:string` | MUST (1) | Family relationship (see values below) |
| Condition | `health:condition` | `xsd:string` | MUST (1) | Name of the condition in the relative |
| Is Deceased | `health:isDeceased` | `xsd:boolean` | MUST (1) | Whether the relative is deceased |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Condition Code | `health:conditionCode` | `xsd:string` | MAY (0..1) | ICD-10 or SNOMED code for the condition |
| Age at Diagnosis | `health:ageAtDiagnosis` | `xsd:integer` | MAY (0..1) | Age of relative when diagnosed |
| Age at Death | `health:ageAtDeath` | `xsd:integer` | MAY (0..1) | Age of relative at death (if deceased) |
| Notes | `health:notes` | `xsd:string` | MAY (0..1) | Free-text notes |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source system |
| Is First Degree | `health:isFirstDegree` | `xsd:boolean` | SHOULD (1) | Computed: whether relative is first-degree (parent, sibling, child) |
| Is Early Onset | `health:isEarlyOnset` | `xsd:boolean` | SHOULD (1) | Computed: whether condition was diagnosed before typical age of onset |

**Valid `relationship` values:** `father`, `mother`, `brother`, `sister`, `son`, `daughter`, `maternalGrandmother`, `maternalGrandfather`, `paternalGrandmother`, `paternalGrandfather`, `maternalAunt`, `maternalUncle`, `paternalAunt`, `paternalUncle`, `other`.

### 10.3 Turtle Example (Annotated)

```turtle
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .

# Father with early-onset Type 2 Diabetes
<urn:uuid:f4m1-h1st-aaaa-bbbb-ccccddddeeee> a health:FamilyHistoryRecord ;

    # --- Required fields ---
    health:relationship "father" ;                         # Family relationship
    health:condition "Type 2 Diabetes Mellitus" ;          # Condition in relative
    health:isDeceased false ;                              # Relative is living
    cascade:dataProvenance cascade:SelfReported ;          # Patient-entered
    cascade:schemaVersion "1.3" ;                          # Schema version

    # --- Clinical detail ---
    health:conditionCode "E11" ;                           # ICD-10 code
    health:ageAtDiagnosis 45 ;                             # Diagnosed at age 45

    # --- Notes ---
    health:notes "Father manages with metformin and diet. Well controlled." ;

    # --- Computed classification flags ---
    health:isFirstDegree true ;                            # Father is first-degree relative
    health:isEarlyOnset true .                             # Onset before age 50 for diabetes
```

### 10.4 JSON-LD Equivalent

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:f4m1-h1st-aaaa-bbbb-ccccddddeeee",
  "@type": "health:FamilyHistoryRecord",
  "health:relationship": "father",
  "health:condition": "Type 2 Diabetes Mellitus",
  "health:isDeceased": false,
  "cascade:dataProvenance": { "@id": "cascade:SelfReported" },
  "cascade:schemaVersion": "1.3",
  "health:conditionCode": "E11",
  "health:ageAtDiagnosis": 45,
  "health:notes": "Father manages with metformin and diet. Well controlled.",
  "health:isFirstDegree": true,
  "health:isEarlyOnset": true
}
```

### 10.5 Provenance -- Family History

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| Patient entry | `cascade:SelfReported` | Patient-entered family medical history |
| EHR import | `cascade:EHRVerified` | Family history from structured EHR data |
| AI extraction | `cascade:AIExtracted` | Extracted from clinical notes |

### 10.6 SHACL Constraints -- Family History

Family history does not currently have a dedicated SHACL shape in the published shapes files. The following constraints are enforced by the SDK serializer and SHOULD be respected by implementers:

| Property | Constraint | Severity |
|---|---|---|
| `health:relationship` | Required, non-empty string, from enumerated values | Violation (SDK-enforced) |
| `health:condition` | Required, non-empty string | Violation (SDK-enforced) |
| `health:isDeceased` | Required, `xsd:boolean` | Violation (SDK-enforced) |
| `cascade:dataProvenance` | Required, valid provenance class | Violation (SDK-enforced) |
| `cascade:schemaVersion` | Required, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation (SDK-enforced) |
| `health:ageAtDiagnosis` | `xsd:integer`, `sh:minInclusive 0` | (SDK-enforced) |
| `health:ageAtDeath` | `xsd:integer`, `sh:minInclusive 0` | (SDK-enforced) |

> **Note:** A formal `clinical:FamilyHistoryShape` will be added to `clinical.shapes.ttl` in a future schema release.

### 10.7 Clinical Significance -- Early Onset and First-Degree Flags

The `health:isFirstDegree` and `health:isEarlyOnset` flags are computed by the SDK at serialization time:

- **`isFirstDegree`** is `true` when the relationship is `father`, `mother`, `brother`, `sister`, `son`, or `daughter`. First-degree relatives share approximately 50% of genetic material and have the strongest predictive value for hereditary risk.
- **`isEarlyOnset`** is `true` when the age at diagnosis falls below the condition-specific threshold for early onset. For example, colorectal cancer diagnosed before age 50, or coronary artery disease before age 55 in males / 65 in females.

These flags enable AI agents and clinical decision support tools to quickly identify high-risk family history patterns without requiring condition-specific medical knowledge in the consumer application.

---

## 11. Coverage / Insurance

### 11.1 Description

Coverage records represent a patient's health insurance plans. The Cascade Protocol supports two types for insurance data, reflecting an ongoing migration:

- **`clinical:CoverageRecord`** (deprecated) -- The original coverage type used by the SDK's `ClinicalRDFSerializer`. Records imported from EHR systems via FHIR `Coverage` resources use this type.
- **`coverage:InsurancePlan`** (preferred) -- The standardized type from the dedicated coverage vocabulary (`coverage.ttl`). This is the target type for new implementations and provides a unified model for both patient-reported and EHR-imported insurance data.

**Migration guidance:** Existing data using `clinical:CoverageRecord` remains valid. New implementations SHOULD use `coverage:InsurancePlan`. The coverage vocabulary unifies `checkup:InsuranceInfo` (patient-reported, Layer 3) and `clinical:CoverageRecord` (EHR-imported, Layer 2) into a single Layer 2 domain model.

**FHIR alignment:** Both types align with `fhir:Coverage`. The `coverage:InsurancePlan` class is defined as a subclass of `prov:Entity` with `rdfs:seeAlso fhir:Coverage`.

**Storage path:** `/coverage/plans/{plan-id}.ttl` (recommended for `coverage:InsurancePlan`)

### 11.2 Properties Table -- CoverageRecord (Legacy)

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Provider Name | `clinical:providerName` | `xsd:string` | MUST (1) | Insurance company name |
| Member ID | `clinical:memberId` | `xsd:string` | MUST (1) | Policy member/subscriber ID |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Group Number | `clinical:groupNumber` | `xsd:string` | MAY (0..1) | Employer group number |
| Plan Name | `clinical:planName` | `xsd:string` | MAY (0..1) | Insurance plan name |
| Plan Type | `clinical:planType` | `xsd:string` | MAY (0..1) | `ppo`, `hmo`, `epo`, `pos`, `hdhp`, etc. |
| Coverage Type | `clinical:coverageType` | `xsd:string` | MAY (0..1) | `primary`, `secondary`, `dental`, `vision` |
| Relationship | `clinical:relationship` | `xsd:string` | MAY (0..1) | Subscriber relationship: `self`, `spouse`, `child`, `other` |
| Effective Period Start | `clinical:effectivePeriodStart` | `xsd:dateTime` | MAY (0..1) | Coverage start date |
| Payor Name | `clinical:payorName` | `xsd:string` | MAY (0..1) | Payor organization name |
| Subscriber ID | `clinical:subscriberId` | `xsd:string` | MAY (0..1) | Subscriber identifier |
| Source Record ID | `health:sourceRecordId` | `xsd:string` | MAY (0..1) | FHIR resource ID from source |

### 11.3 Properties Table -- InsurancePlan (Preferred)

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Provider Name | `coverage:providerName` | `xsd:string` | MUST (1) | Insurance company name |
| Member ID | `coverage:memberId` | `xsd:string` | MUST (1) | Policy member ID |
| Coverage Type | `coverage:coverageType` | `xsd:string` | MUST (1) | `primary`, `secondary`, `dental`, `vision` |
| Data Provenance | `cascade:dataProvenance` | (Object) | MUST (1) | How data was generated |
| Schema Version | `cascade:schemaVersion` | `xsd:string` | MUST (1) | Schema version |
| Group Number | `coverage:groupNumber` | `xsd:string` | SHOULD (0..1) | Employer group number |
| Plan Type | `coverage:planType` | `xsd:string` | SHOULD (0..1) | `hmo`, `ppo`, `epo`, `pos`, `hdhp`, `medicare`, `medicaid`, `tricare`, `other` |
| Effective Start | `coverage:effectiveStart` | `xsd:date` | SHOULD (0..1) | Coverage start date |
| Subscriber Relationship | `coverage:subscriberRelationship` | `xsd:string` | SHOULD (0..1) | `self`, `spouse`, `child`, `parent`, `other` |
| Plan Name | `coverage:planName` | `xsd:string` | MAY (0..1) | Insurance plan name |
| Effective End | `coverage:effectiveEnd` | `xsd:date` | MAY (0..1) | Coverage end date |
| Subscriber ID | `coverage:subscriberId` | `xsd:string` | MAY (0..1) | Subscriber identifier |
| Subscriber Name | `coverage:subscriberName` | `xsd:string` | MAY (0..1) | Subscriber full name |
| Rx BIN | `coverage:rxBin` | `xsd:string` | MAY (0..1) | Pharmacy benefit BIN |
| Rx PCN | `coverage:rxPcn` | `xsd:string` | MAY (0..1) | Pharmacy benefit PCN |
| Rx Group | `coverage:rxGroup` | `xsd:string` | MAY (0..1) | Pharmacy benefit group |

### 11.4 Turtle Example -- CoverageRecord (Legacy)

```turtle
@prefix clinical: <https://ns.cascadeprotocol.org/clinical/v1#> .
@prefix health:   <https://ns.cascadeprotocol.org/health/v1#> .
@prefix cascade:  <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .

# Insurance coverage from EHR import (legacy CoverageRecord type)
<urn:uuid:c0vr-0001-aaaa-bbbb-ccccddddeeee> a clinical:CoverageRecord ;

    # --- Required fields ---
    clinical:providerName "Blue Cross Blue Shield" ;       # Insurance company
    clinical:memberId "BCBS-AR-2020-78452" ;               # Member ID
    cascade:dataProvenance cascade:ClinicalGenerated ;     # From EHR import
    cascade:schemaVersion "1.3" ;                          # Schema version

    # --- Plan details ---
    clinical:groupNumber "GRP-98765" ;                     # Employer group
    clinical:planName "Blue PPO Select" ;                  # Plan name
    clinical:planType "ppo" ;                              # Plan type
    clinical:coverageType "primary" ;                      # Primary coverage
    clinical:relationship "self" ;                         # Patient is subscriber

    # --- Coverage period ---
    clinical:effectivePeriodStart "2020-01-01T00:00:00Z"^^xsd:dateTime ;

    # --- Payor and subscriber ---
    clinical:payorName "Blue Cross Blue Shield of Oregon" ;
    clinical:subscriberId "BCBS-AR-2020-78452" ;

    # --- Source tracking ---
    health:sourceRecordId "ehr-coverage-2020-0101-001" .   # FHIR Coverage ID
```

### 11.5 Turtle Example -- InsurancePlan (Preferred)

```turtle
@prefix coverage: <https://ns.cascadeprotocol.org/coverage/v1#> .
@prefix cascade:  <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd:      <http://www.w3.org/2001/XMLSchema#> .

# Insurance plan using the preferred coverage vocabulary
<urn:uuid:d1e2f3a4-b5c6-7890-plan-123456789abc> a coverage:InsurancePlan ;

    # --- Required fields ---
    coverage:providerName "Blue Cross Blue Shield" ;       # Insurance company
    coverage:memberId "BCBS-AR-2020-78452" ;               # Member ID
    coverage:coverageType "primary" ;                      # Primary coverage
    cascade:dataProvenance cascade:SelfReported ;          # Patient-entered
    cascade:schemaVersion "1.3" ;                          # Schema version

    # --- Plan identification ---
    coverage:groupNumber "GRP-98765" ;                     # Employer group
    coverage:planName "Blue PPO Select" ;                  # Plan name
    coverage:planType "ppo" ;                              # Plan type

    # --- Coverage period ---
    coverage:effectiveStart "2020-01-01"^^xsd:date ;       # Start date (xsd:date)
    coverage:subscriberRelationship "self" ;               # Patient is subscriber

    # --- Subscriber details ---
    coverage:subscriberId "BCBS-AR-2020-78452" ;           # Subscriber ID
    coverage:subscriberName "Alex Rivera" ;                # Subscriber name

    # --- Pharmacy benefits ---
    coverage:rxBin "004336" ;                              # Rx BIN
    coverage:rxPcn "ADV" ;                                 # Rx PCN
    coverage:rxGroup "RX9876" .                            # Rx Group
```

### 11.6 JSON-LD Equivalent -- InsurancePlan

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "urn:uuid:d1e2f3a4-b5c6-7890-plan-123456789abc",
  "@type": "coverage:InsurancePlan",
  "coverage:providerName": "Blue Cross Blue Shield",
  "coverage:memberId": "BCBS-AR-2020-78452",
  "coverage:coverageType": "primary",
  "cascade:dataProvenance": { "@id": "cascade:SelfReported" },
  "cascade:schemaVersion": "1.3",
  "coverage:groupNumber": "GRP-98765",
  "coverage:planName": "Blue PPO Select",
  "coverage:planType": "ppo",
  "coverage:effectiveStart": {
    "@value": "2020-01-01",
    "@type": "xsd:date"
  },
  "coverage:subscriberRelationship": "self",
  "coverage:subscriberId": "BCBS-AR-2020-78452",
  "coverage:subscriberName": "Alex Rivera",
  "coverage:rxBin": "004336",
  "coverage:rxPcn": "ADV",
  "coverage:rxGroup": "RX9876"
}
```

### 11.7 Provenance -- Coverage

| Source | `cascade:dataProvenance` | Typical Use |
|---|---|---|
| EHR import | `cascade:ClinicalGenerated` | Coverage from hospital/clinic EHR |
| Patient entry | `cascade:SelfReported` | Patient-entered insurance info (intake forms) |
| EHR verified | `cascade:EHRVerified` | Verified coverage from patient portal |

### 11.8 SHACL Constraints -- Coverage

The `coverage:InsurancePlanShape` in `coverage.shapes.ttl` enforces:

| Property | Constraint | Severity |
|---|---|---|
| `coverage:providerName` | `sh:minCount 1`, `sh:minLength 1`, `xsd:string` | Violation |
| `coverage:memberId` | `sh:minCount 1`, `sh:minLength 1`, `xsd:string` | Violation |
| `coverage:coverageType` | `sh:minCount 1`, `sh:in ("primary", "secondary", "dental", "vision")` | Violation |
| `cascade:dataProvenance` | `sh:minCount 1`, valid provenance class | Violation |
| `cascade:schemaVersion` | `sh:minCount 1`, `sh:pattern "^[0-9]+\\.[0-9]+$"` | Violation |
| `coverage:groupNumber` | `xsd:string`, `sh:maxCount 1` | Warning |
| `coverage:planType` | `sh:in ("hmo", "ppo", "epo", "pos", "hdhp", "medicare", "medicaid", "tricare", "other")` | Warning |
| `coverage:effectiveStart` | `xsd:date`, `sh:maxCount 1` | Warning |
| `coverage:subscriberRelationship` | `sh:in ("self", "spouse", "child", "parent", "other")` | Warning |
| `coverage:planName` | `xsd:string`, `sh:maxCount 1` | Info |
| `coverage:effectiveEnd` | `xsd:date`, `sh:maxCount 1` | Info |
| `coverage:subscriberId` | `xsd:string`, `sh:maxCount 1` | Info |
| `coverage:subscriberName` | `xsd:string`, `sh:maxCount 1` | Info |
| `coverage:rxBin` | `xsd:string`, `sh:maxCount 1` | Info |
| `coverage:rxPcn` | `xsd:string`, `sh:maxCount 1` | Info |
| `coverage:rxGroup` | `xsd:string`, `sh:maxCount 1` | Info |

> **Note on deprecation:** The legacy `clinical:CoverageRecord` type does not have a dedicated SHACL shape. Validation of legacy records relies on the SDK serializer constraints. New implementations SHOULD use `coverage:InsurancePlan` with the `coverage:InsurancePlanShape` validation.

---

## 12. Wellness Observations

### 12.1 Description

Wellness observations represent consumer-device-generated health data from wearables and personal health devices. Unlike clinical vital signs (Section 6), which are point-in-time observations from clinical encounters, wellness observations use a **time-series container pattern** where a top-level data type (e.g., `health:HeartRateData`) contains a history list of daily snapshots.

The wellness data model is designed for high-frequency, device-generated data that accumulates over days, weeks, and months. Each data domain has its own file within the `/wellness/` directory of the Cascade Pod.

**Provenance:** Wellness observations typically carry `cascade:DeviceGenerated` (direct from wearable) or `cascade:ConsumerWellness` (aggregated from a platform like Apple Health).

### 12.2 Time-Series Container Pattern

All wellness observations follow this structural pattern:

```turtle
<#container-id> a health:DataType ;
    health:historyProperty (
        [ a health:SnapshotType ; cascade:date "2026-01-20T00:00:00Z"^^xsd:dateTime ; ... ]
        [ a health:SnapshotType ; cascade:date "2026-01-21T00:00:00Z"^^xsd:dateTime ; ... ]
        [ a health:SnapshotType ; cascade:date "2026-01-22T00:00:00Z"^^xsd:dateTime ; ... ]
    ) .
```

The container resource uses a **fragment identifier** (e.g., `<#heart-rate>`) rather than a UUID, because it represents an aggregate rather than a discrete clinical event. Daily snapshots are anonymous **blank nodes** within an RDF list.

Each daily snapshot includes:
- `cascade:date` -- The date of the observation
- Metric-specific properties -- Values, counts, and quality indicators
- `prov:wasGeneratedBy` -- Inline provenance activity identifying the source device

### 12.3 Heart Rate

Heart rate data is stored as `health:HeartRateData` with separate history lists for resting and walking heart rates.

#### 12.3.1 Properties Table -- HeartRateData Container

| Property | Predicate URI | Type | Description |
|---|---|---|---|
| Resting HR (latest) | `health:restingHeartRate` | (Blank node) | Most recent resting HR reading |
| Walking HR (latest) | `health:walkingHeartRate` | (Blank node) | Most recent walking HR reading |
| Resting HR History | `health:restingHeartRateHistory` | (RDF List) | Daily resting HR readings |
| Walking HR History | `health:walkingHeartRateHistory` | (RDF List) | Daily walking HR readings |

#### 12.3.2 Properties Table -- DailyVitalReading (Heart Rate)

| Property | Predicate URI | XSD Type | Description |
|---|---|---|---|
| SNOMED Code | `fhir:code` | (URI) | `sct:364075005` (Heart rate) |
| LOINC Code | `cascade:loincCode` | (URI) | `loinc:40443-4` (resting) or `loinc:89270-3` (walking) |
| Value | `fhir:valueQuantity / fhir:value` | `xsd:double` | Heart rate in bpm |
| Unit | `fhir:valueQuantity / fhir:unit` | `xsd:string` | "bpm" |
| Unit System | `fhir:valueQuantity / fhir:system` | (URI) | `ucum:` |
| Date | `cascade:date` | `xsd:dateTime` | Date of reading |
| Sample Count | `cascade:sampleCount` | `xsd:integer` | Number of samples aggregated |
| Provenance | `prov:wasGeneratedBy` | (Blank node) | Source device activity |

#### 12.3.3 Turtle Example -- Heart Rate

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix fhir:    <http://hl7.org/fhir/> .
@prefix sct:     <http://snomed.info/sct/> .
@prefix loinc:   <http://loinc.org/rdf#> .
@prefix ucum:    <http://unitsofmeasure.org/> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:    <http://www.w3.org/ns/prov#> .

# Heart rate data container with daily resting heart rate history
<#heart-rate> a health:HeartRateData ;
    health:restingHeartRateHistory (
        [ a health:DailyVitalReading ;
            fhir:code sct:364075005 ;
            cascade:loincCode loinc:40443-4 ;
            fhir:valueQuantity [ fhir:value "68"^^xsd:double ; fhir:unit "bpm" ; fhir:system ucum: ] ;
            cascade:date "2026-01-20T07:00:00Z"^^xsd:dateTime ;
            cascade:sampleCount "142"^^xsd:integer ;
            prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Apple Watch Series 9" ] ]
        [ a health:DailyVitalReading ;
            fhir:code sct:364075005 ;
            cascade:loincCode loinc:40443-4 ;
            fhir:valueQuantity [ fhir:value "65"^^xsd:double ; fhir:unit "bpm" ; fhir:system ucum: ] ;
            cascade:date "2026-01-21T07:00:00Z"^^xsd:dateTime ;
            cascade:sampleCount "156"^^xsd:integer ;
            prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Apple Watch Series 9" ] ]
    ) .
```

### 12.4 Blood Pressure (Device)

Device blood pressure data uses `health:BloodPressureData` with the `health:bloodPressureHistory` list. Each reading is a `fhir:Observation` with two `fhir:component` entries for systolic and diastolic values.

#### 12.4.1 Turtle Example -- Blood Pressure

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix fhir:    <http://hl7.org/fhir/> .
@prefix sct:     <http://snomed.info/sct/> .
@prefix loinc:   <http://loinc.org/rdf#> .
@prefix ucum:    <http://unitsofmeasure.org/> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:    <http://www.w3.org/ns/prov#> .

# Home blood pressure data from Omron BP monitor
<#blood-pressure> a health:BloodPressureData ;
    health:bloodPressureHistory (
        [ a fhir:Observation ;
            fhir:code sct:75367002 ;                       # Blood pressure (observable)
            cascade:loincCode loinc:85354-9 ;              # Blood pressure panel
            fhir:component (
                [ fhir:code sct:271649006 ;                # Systolic BP
                  fhir:valueQuantity [ fhir:value "132"^^xsd:double ; fhir:unit "mmHg" ;
                                       fhir:system ucum: ; fhir:code "mm[Hg]" ] ]
                [ fhir:code sct:271650006 ;                # Diastolic BP
                  fhir:valueQuantity [ fhir:value "82"^^xsd:double ; fhir:unit "mmHg" ;
                                       fhir:system ucum: ; fhir:code "mm[Hg]" ] ]
            ) ;
            fhir:effectiveDateTime "2026-01-20T07:30:00Z"^^xsd:dateTime ;
            prov:wasGeneratedBy [ a prov:Activity ; prov:label "Omron Evolv" ] ]
    ) .
```

### 12.5 Activity

Activity data uses `health:ActivityData` with the `health:dailyActivityHistory` list. Each snapshot captures steps, active energy, exercise minutes, and stand hours.

#### 12.5.1 Properties Table -- DailyActivitySnapshot

| Property | Predicate URI | XSD Type | Description |
|---|---|---|---|
| Date | `cascade:date` | `xsd:dateTime` | Date of activity |
| Steps | `health:steps` | `xsd:integer` | Total steps for the day |
| Active Energy | `health:activeEnergyKcal` | `xsd:decimal` | Active calories burned (kcal) |
| Exercise Minutes | `health:exerciseMinutes` | `xsd:integer` | Minutes of exercise |
| Stand Hours | `health:standHours` | `xsd:integer` | Hours with standing activity |
| Provenance | `prov:wasGeneratedBy` | (Blank node) | Source device activity |

#### 12.5.2 Turtle Example -- Activity

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:    <http://www.w3.org/ns/prov#> .

# Activity data from Apple Watch
<#activity> a health:ActivityData ;
    health:dailyActivityHistory (
        [ a health:DailyActivitySnapshot ;
            cascade:date "2026-01-20T00:00:00Z"^^xsd:dateTime ;
            health:steps "7842"^^xsd:integer ;
            health:activeEnergyKcal "312"^^xsd:decimal ;
            health:exerciseMinutes "22"^^xsd:integer ;
            health:standHours "10"^^xsd:integer ;
            prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Apple Watch Series 9" ] ]
        [ a health:DailyActivitySnapshot ;
            cascade:date "2026-01-21T00:00:00Z"^^xsd:dateTime ;
            health:steps "9234"^^xsd:integer ;
            health:activeEnergyKcal "385"^^xsd:decimal ;
            health:exerciseMinutes "35"^^xsd:integer ;
            health:standHours "11"^^xsd:integer ;
            prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Apple Watch Series 9" ] ]
    ) .
```

### 12.6 Sleep

Sleep data uses `health:SleepData` with the `health:dailySleepHistory` list. Each snapshot captures duration and quality.

#### 12.6.1 Properties Table -- DailySleepSnapshot

| Property | Predicate URI | XSD Type | Description |
|---|---|---|---|
| Date | `cascade:date` | `xsd:dateTime` | Date of sleep period |
| Duration | `health:durationHours` | `xsd:decimal` | Total sleep duration in hours |
| Sleep Quality | `health:sleepQuality` | (URI) | Quality: `health:Excellent`, `health:Good`, `health:Fair`, `health:Poor` |
| Provenance | `prov:wasGeneratedBy` | (Blank node) | Source device activity |

#### 12.6.2 Turtle Example -- Sleep

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:    <http://www.w3.org/ns/prov#> .

# Sleep data from Apple Watch
<#sleep> a health:SleepData ;
    health:dailySleepHistory (
        [ a health:DailySleepSnapshot ;
            cascade:date "2026-01-20T00:00:00Z"^^xsd:dateTime ;
            health:durationHours "7.2"^^xsd:decimal ;
            health:sleepQuality health:Good ;
            prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Apple Watch Series 9" ] ]
        [ a health:DailySleepSnapshot ;
            cascade:date "2026-01-21T00:00:00Z"^^xsd:dateTime ;
            health:durationHours "6.8"^^xsd:decimal ;
            health:sleepQuality health:Fair ;
            prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Apple Watch Series 9" ] ]
    ) .
```

### 12.7 Heart Rate Variability (HRV)

HRV data uses `health:HRVData` with both a latest reading (`health:heartRateVariability`) and a history list (`health:hrvHistory`). The SDK also computes `health:HRVStatistics` for period-based summaries.

#### 12.7.1 Properties Table -- HRVStatistics

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Mean HRV | `health:hrvMean` | `xsd:double` | MUST (1) | Average SDNN in ms |
| Sample Count | `health:hrvSampleCount` | `xsd:integer` | MUST (1) | Number of readings |
| Period Start | `health:periodStart` | `xsd:dateTime` | MUST (1) | Start of measurement window |
| Period End | `health:periodEnd` | `xsd:dateTime` | MUST (1) | End of measurement window |
| Median | `health:hrvMedian` | `xsd:double` | MAY (0..1) | Median SDNN |
| Std Dev | `health:hrvStdDev` | `xsd:double` | MAY (0..1) | Standard deviation |
| Minimum | `health:hrvMin` | `xsd:double` | MAY (0..1) | Lowest reading |
| Maximum | `health:hrvMax` | `xsd:double` | MAY (0..1) | Highest reading |
| Trend Direction | `health:hrvTrendDirection` | `xsd:string` | MAY (0..1) | `improving`, `declining`, `stable`, `unknown` |

#### 12.7.2 Turtle Example -- HRV

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix fhir:    <http://hl7.org/fhir/> .
@prefix sct:     <http://snomed.info/sct/> .
@prefix loinc:   <http://loinc.org/rdf#> .
@prefix ucum:    <http://unitsofmeasure.org/> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:    <http://www.w3.org/ns/prov#> .

# HRV data with statistics and daily history
<#hrv> a health:HRVData ;
    health:heartRateVariability [
        a health:VitalSignReading ;
        fhir:code sct:80404004 ;
        cascade:loincCode loinc:80404-7 ;
        fhir:valueQuantity [ fhir:value "42.5"^^xsd:double ; fhir:unit "ms" ; fhir:system ucum: ] ;
        cascade:date "2026-02-18T07:00:00Z"^^xsd:dateTime ;
        prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Apple Watch Series 9" ]
    ] ;
    health:hasHRVStatistics [
        a health:HRVStatistics ;
        health:hrvMean "38.4"^^xsd:double ;
        health:hrvSampleCount "28"^^xsd:integer ;
        health:periodStart "2026-01-20T00:00:00Z"^^xsd:dateTime ;
        health:periodEnd "2026-02-18T00:00:00Z"^^xsd:dateTime ;
        health:hrvMedian "37.0"^^xsd:double ;
        health:hrvMin "25.0"^^xsd:double ;
        health:hrvMax "52.0"^^xsd:double ;
        health:hrvTrendDirection "stable"
    ] .
```

### 12.8 VO2 Max

VO2 Max data uses a `health:VO2MaxStatistics` container within the body measurements section of the health profile. It includes a fitness classification based on age and sex.

#### 12.8.1 Properties Table -- VO2MaxStatistics

| Property | Predicate URI | XSD Type | Cardinality | Description |
|---|---|---|---|---|
| Mean VO2 Max | `health:vo2Mean` | `xsd:double` | MUST (1) | Average VO2 Max (mL/kg/min) |
| Sample Count | `health:vo2SampleCount` | `xsd:integer` | MUST (1) | Number of measurements |
| Fitness Classification | `health:fitnessClassification` | `xsd:string` | MUST (1) | `veryPoor`, `poor`, `fair`, `good`, `excellent`, `superior` |
| Period Start | `health:periodStart` | `xsd:dateTime` | SHOULD (0..1) | Start of measurement window |
| Period End | `health:periodEnd` | `xsd:dateTime` | SHOULD (0..1) | End of measurement window |
| Minimum | `health:vo2Min` | `xsd:double` | MAY (0..1) | Lowest reading |
| Maximum | `health:vo2MaxValue` | `xsd:double` | MAY (0..1) | Highest reading |
| Trend Direction | `health:vo2TrendDirection` | `xsd:string` | MAY (0..1) | `improving`, `declining`, `stable`, `unknown` |
| Sparse Data | `health:isSparseData` | `xsd:boolean` | MAY (0..1) | Whether data is sparse |

#### 12.8.2 Turtle Example -- VO2 Max

```turtle
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .

# VO2 Max statistics within body measurements
<#body-measurements> a health:BodyMeasurements ;
    health:VO2MaxStatistics [
        a health:VO2MaxStatistics ;
        health:vo2Mean "34.2"^^xsd:double ;
        health:vo2SampleCount "12"^^xsd:integer ;
        health:fitnessClassification "fair" ;
        health:periodStart "2025-08-20T00:00:00Z"^^xsd:dateTime ;
        health:periodEnd "2026-02-18T00:00:00Z"^^xsd:dateTime ;
        health:vo2Min "32.1"^^xsd:double ;
        health:vo2MaxValue "36.8"^^xsd:double ;
        health:vo2TrendDirection "stable"
    ] .
```

### 12.9 Body Measurements

Body measurements are stored within a `health:BodyMeasurements` container and include body mass, height, BMI, body temperature, SpO2, and blood glucose. Each measurement uses the `health:VitalSignReading` type with FHIR-aligned coding.

#### 12.9.1 Metrics Table

| Metric | Property | SNOMED Code | LOINC Code | Unit |
|---|---|---|---|---|
| Body Mass | `health:bodyMass` | `27113001` | `29463-7` | kg |
| Body Height | `health:height` | `50373000` | `8302-2` | cm |
| BMI | `health:computedBMI` | `60621009` | `39156-5` | kg/m2 |
| Body Temperature | `health:bodyTemperature` | `386725007` | `8310-5` | degC |
| Oxygen Saturation | `health:oxygenSaturation` | `431314004` | `2708-6` | % |
| Blood Glucose | `health:bloodGlucose` | `33747003` | `2345-7` | mg/dL |

#### 12.9.2 Turtle Example -- Body Measurements

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix health:  <https://ns.cascadeprotocol.org/health/v1#> .
@prefix fhir:    <http://hl7.org/fhir/> .
@prefix sct:     <http://snomed.info/sct/> .
@prefix loinc:   <http://loinc.org/rdf#> .
@prefix ucum:    <http://unitsofmeasure.org/> .
@prefix xsd:     <http://www.w3.org/2001/XMLSchema#> .
@prefix prov:    <http://www.w3.org/ns/prov#> .

# Body measurements container
<#body-measurements> a health:BodyMeasurements ;

    # --- Body mass (latest reading) ---
    health:bodyMass [
        a health:VitalSignReading ;
        fhir:code sct:27113001 ;
        cascade:loincCode loinc:29463-7 ;
        fhir:valueQuantity [ fhir:value "91.2"^^xsd:double ; fhir:unit "kg" ; fhir:system ucum: ] ;
        cascade:date "2026-02-15T07:30:00Z"^^xsd:dateTime ;
        prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Withings Body+" ]
    ] ;

    # --- Height ---
    health:height [
        a health:VitalSignReading ;
        fhir:code sct:50373000 ;
        cascade:loincCode loinc:8302-2 ;
        fhir:valueQuantity [ fhir:value "178"^^xsd:double ; fhir:unit "cm" ; fhir:system ucum: ] ;
        cascade:date "2025-12-01T10:00:00Z"^^xsd:dateTime
    ] ;

    # --- Computed BMI ---
    health:computedBMI [
        a health:VitalSignReading ;
        fhir:code sct:60621009 ;
        cascade:loincCode loinc:39156-5 ;
        fhir:valueQuantity [ fhir:value "28.8"^^xsd:double ; fhir:unit "kg/m2" ; fhir:system ucum: ] ;
        cascade:date "2026-02-15T07:30:00Z"^^xsd:dateTime
    ] ;

    # --- Body temperature ---
    health:bodyTemperature [
        a health:VitalSignReading ;
        fhir:code sct:386725007 ;
        cascade:loincCode loinc:8310-5 ;
        fhir:valueQuantity [ fhir:value "36.6"^^xsd:double ; fhir:unit "degC" ; fhir:system ucum: ] ;
        cascade:date "2026-02-18T08:00:00Z"^^xsd:dateTime
    ] ;

    # --- Oxygen saturation (SpO2) ---
    health:oxygenSaturation [
        a health:VitalSignReading ;
        fhir:code sct:431314004 ;
        cascade:loincCode loinc:2708-6 ;
        fhir:valueQuantity [ fhir:value "97"^^xsd:double ; fhir:unit "%" ; fhir:system ucum: ] ;
        cascade:date "2026-02-18T08:00:00Z"^^xsd:dateTime ;
        prov:wasGeneratedBy [ a prov:Activity ; cascade:sourceType "healthKit" ; prov:label "Apple Watch Series 9" ]
    ] .
```

### 12.10 SHACL Constraints -- Wellness Observations

The `health.shapes.ttl` file provides shapes for wellness statistical summaries:

**`health:VO2MaxStatisticsShape`:**

| Property | Constraint | Severity |
|---|---|---|
| `health:vo2Mean` | `sh:minCount 1`, `xsd:double`, `sh:minInclusive 0` | Violation |
| `health:vo2SampleCount` | `sh:minCount 1`, `xsd:integer`, `sh:minInclusive 1` | Violation |
| `health:fitnessClassification` | `sh:minCount 1`, `sh:in ("veryPoor", "poor", "fair", "good", "excellent", "superior")` | Violation |
| `health:periodStart` | `xsd:dateTime`, `sh:maxCount 1` | Warning |
| `health:periodEnd` | `xsd:dateTime`, `sh:maxCount 1` | Warning |

**`health:HRVStatisticsShape`:**

| Property | Constraint | Severity |
|---|---|---|
| `health:hrvMean` | `sh:minCount 1`, `xsd:double`, `sh:minInclusive 0` | Violation |
| `health:hrvSampleCount` | `sh:minCount 1`, `xsd:integer`, `sh:minInclusive 1` | Violation |
| `health:periodStart` | `sh:minCount 1`, `xsd:dateTime` | Violation |
| `health:periodEnd` | `sh:minCount 1`, `xsd:dateTime` | Violation |
| `health:hrvTrendDirection` | `sh:in ("improving", "declining", "stable", "unknown")` | Info |

**`health:BPStatisticsShape`:**

| Property | Constraint | Severity |
|---|---|---|
| `health:bpMeanSystolic` | `sh:minCount 1`, `xsd:double`, range 40-300 | Violation |
| `health:bpMeanDiastolic` | `sh:minCount 1`, `xsd:double`, range 20-200 | Violation |
| `health:bpCategory` | `sh:minCount 1`, `sh:in ("normal", "elevated", "hypertension_stage1", "hypertension_stage2", "hypertensive_crisis")` | Violation |
| `health:bpSampleCount` | `xsd:integer`, `sh:minInclusive 1` | Warning |

**`health:ActivitySnapshotShape`:**

| Property | Constraint | Severity |
|---|---|---|
| `health:averageDailySteps` | `xsd:integer`, `sh:minInclusive 0` | Warning |
| `health:exerciseMinutesWeekly` | `xsd:integer`, `sh:minInclusive 0` | Info |
| `health:standHoursDaily` | `xsd:integer`, range 0-24 | Info |

**`health:SleepSnapshotShape`:**

| Property | Constraint | Severity |
|---|---|---|
| `health:averageDurationHours` | `xsd:decimal`, range 0-24 | Warning |
| `health:sleepQuality` | `xsd:string` | Info |

### 12.11 JSON-LD Equivalent -- Wellness Observations

Wellness observation containers can be expressed in JSON-LD. Due to the nested blank node structure, the JSON-LD representation is more verbose:

```json
{
  "@context": "https://ns.cascadeprotocol.org/context/v1/cascade.jsonld",
  "@id": "#activity",
  "@type": "health:ActivityData",
  "health:dailyActivityHistory": {
    "@list": [
      {
        "@type": "health:DailyActivitySnapshot",
        "cascade:date": { "@value": "2026-01-20T00:00:00Z", "@type": "xsd:dateTime" },
        "health:steps": 7842,
        "health:activeEnergyKcal": 312,
        "health:exerciseMinutes": 22,
        "health:standHours": 10,
        "prov:wasGeneratedBy": {
          "@type": "prov:Activity",
          "cascade:sourceType": "healthKit",
          "prov:label": "Apple Watch Series 9"
        }
      }
    ]
  }
}
```

---

## 13. Comprehensive Provenance Model

### 13.1 Description

The Cascade Protocol integrates the W3C PROV-O ontology for expressing data lineage. This section documents the full provenance model, including how provenance attaches to records, activity chains, agent attribution, and guidelines for AI agents interpreting provenance.

The provenance model operates at two levels:

1. **Record-level provenance** -- The `cascade:dataProvenance` triple on every resource (covered in Section 1.6 and each data type section).
2. **Activity-level provenance** -- W3C PROV-O `prov:Activity`, `prov:wasGeneratedBy`, and `prov:wasAttributedTo` triples that describe the detailed lineage of how data was generated.

### 13.2 Complete Provenance Taxonomy

The full provenance class hierarchy defined in `core.ttl`:

```
cascade:DataProvenance (base class, subclass of prov:Entity)
|
+-- cascade:ConsumerGenerated
|   |   Data from personal devices in non-clinical settings
|   |
|   +-- cascade:DeviceGenerated
|   |       Consumer health device (Apple Watch, BP cuff, glucose meter)
|   |
|   +-- cascade:SelfReported
|   |       Patient manual entry (symptom logs, intake forms)
|   |
|   +-- cascade:ConsumerWellness
|           Aggregated wellness platform (Apple Health, Google Fit)
|
+-- cascade:ClinicalGenerated
    |   Data from clinical settings under provider supervision
    |
    +-- cascade:EHRVerified
    |       Imported from verified EHR (Epic MyChart, Cerner)
    |
    +-- cascade:ScannedDocument
    |       Extracted from scanned/photographed clinical documents
    |
    +-- cascade:AIExtracted
            Extracted from clinical documents using AI/NLP
```

**Disjointness:** `cascade:ConsumerGenerated` and `cascade:ClinicalGenerated` are declared `owl:disjointWith` each other. A record cannot be both consumer-generated and clinical-generated.

### 13.3 How Provenance Attaches to Records

Every Cascade Protocol resource MUST include a `cascade:dataProvenance` triple:

```turtle
# Record-level provenance (REQUIRED on all resources)
<urn:uuid:abc-123> cascade:dataProvenance cascade:EHRVerified .
```

Wellness observations additionally carry **inline activity provenance** on each daily snapshot:

```turtle
# Activity-level provenance (inline on daily snapshots)
[ a health:DailyVitalReading ;
    ...
    prov:wasGeneratedBy [
        a prov:Activity ;
        cascade:sourceType "healthKit" ;       # Source platform
        prov:label "Apple Watch Series 9"      # Device name
    ]
] .
```

### 13.4 Activity Chains and Generation Events

For complex data pipelines (e.g., AI extraction from scanned documents), provenance can be chained:

```turtle
# A medication extracted from a scanned lab report
<urn:uuid:med-from-scan-001> a health:MedicationRecord ;
    health:medicationName "Lisinopril" ;
    cascade:dataProvenance cascade:AIExtracted ;
    cascade:schemaVersion "1.3" ;
    prov:wasGeneratedBy <urn:uuid:extraction-activity-001> .

# The AI extraction activity
<urn:uuid:extraction-activity-001> a prov:Activity ;
    prov:label "AI medication extraction from scanned document" ;
    prov:wasAssociatedWith <urn:uuid:ai-agent-001> ;
    prov:used <urn:uuid:scanned-doc-001> ;
    prov:startedAtTime "2026-02-19T10:00:00Z"^^xsd:dateTime ;
    prov:endedAtTime "2026-02-19T10:00:05Z"^^xsd:dateTime .

# The AI agent
<urn:uuid:ai-agent-001> a prov:SoftwareAgent ;
    prov:label "Cascade AI Extractor v2.1" ;
    cascade:agentType "aiExtractor" .

# The source document
<urn:uuid:scanned-doc-001> a prov:Entity ;
    prov:label "Scanned lab report 2026-01-15" ;
    cascade:dataProvenance cascade:ScannedDocument .
```

### 13.5 Agent Attribution Patterns

The Cascade Protocol recognizes several agent types:

| Agent Type | PROV-O Class | `cascade:agentType` | Description |
|---|---|---|---|
| Patient | `prov:Person` | `patient` | The data subject entering self-reported data |
| Software | `prov:SoftwareAgent` | `sdkSerializer` | SDK serializer producing RDF output |
| AI Extractor | `prov:SoftwareAgent` | `aiExtractor` | AI/NLP agent extracting structured data |
| Device | `prov:SoftwareAgent` | `device` | Consumer health device |
| EHR System | `prov:SoftwareAgent` | `ehrSystem` | Source EHR system |

### 13.6 AIGenerated Provenance

When an AI agent creates or synthesizes data (as opposed to extracting it from an existing document), the provenance should be explicit:

```turtle
# An AI-generated clinical summary
<urn:uuid:summary-001> a cascade:ClinicalSummary ;
    cascade:dataProvenance cascade:AIExtracted ;
    cascade:schemaVersion "1.3" ;
    prov:wasGeneratedBy [
        a prov:Activity ;
        prov:label "AI clinical summary generation" ;
        prov:wasAssociatedWith [
            a prov:SoftwareAgent ;
            prov:label "Claude (Anthropic)" ;
            cascade:agentType "aiAgent" ;
            cascade:agentVersion "claude-opus-4-6"
        ]
    ] .
```

**Key principle:** AI-generated content MUST always carry `cascade:AIExtracted` provenance (or a future `cascade:AIGenerated` subclass when defined). Consumers MUST be able to distinguish AI-generated content from clinician-verified or device-measured data.

### 13.7 Provenance Trust Levels for AI Agents

When an AI agent reads Cascade Protocol data, it SHOULD interpret provenance to determine trust levels:

| Provenance Class | Trust Level | Agent Guidance |
|---|---|---|
| `cascade:EHRVerified` | **High** | Treat as authoritative clinical data. Safe for clinical decision support. |
| `cascade:ClinicalGenerated` | **High** | Clinical-setting data. Safe for clinical reasoning. |
| `cascade:DeviceGenerated` | **Medium** | Consumer device data. Reliable for trends but may have accuracy limitations. |
| `cascade:ConsumerWellness` | **Medium** | Aggregated platform data. Good for trends, not for point-of-care decisions. |
| `cascade:SelfReported` | **Low-Medium** | Patient-entered data. Verify with clinical sources when possible. |
| `cascade:AIExtracted` | **Low** | AI-extracted data. Should be verified by a human before clinical use. |
| `cascade:ScannedDocument` | **Low** | OCR/scan data. May contain errors from image quality issues. |

**No Silent Inference policy:** When an AI agent makes inferences from provenance data, it MUST disclose the provenance sources and confidence levels. For example: "Based on your EHR-verified medication list (high confidence) and self-reported supplement intake (medium confidence), there is a potential interaction between..."

### 13.8 Provenance in Export Manifests

When a Cascade Pod is exported, the manifest file (`manifest.ttl`) includes W3C PROV-O metadata describing the export event:

```turtle
@prefix prov: <http://www.w3.org/ns/prov#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

<#export> a prov:Activity ;
    prov:label "Cascade Pod Export" ;
    prov:startedAtTime "2026-02-19T14:00:00Z"^^xsd:dateTime ;
    prov:endedAtTime "2026-02-19T14:00:03Z"^^xsd:dateTime ;
    prov:wasAssociatedWith [
        a prov:SoftwareAgent ;
        prov:label "Cascade Checkup v1.0" ;
        cascade:agentType "sdkSerializer" ;
        cascade:sdkVersion "1.3"
    ] ;
    prov:generated <#pod> .

<#pod> a prov:Collection ;
    prov:label "Alex Rivera Health Pod" ;
    cascade:schemaVersion "1.3" ;
    cascade:exportFormat "turtle" ;
    cascade:fileCount "15"^^xsd:integer .
```

---

## 14. Pod Structure Conventions

### 14.1 Description

This section provides a summary of the Cascade Protocol Pod Structure specification. The full specification is available as a standalone document at `docs/spec/pod-structure.md`.

A Cascade Protocol **Pod** is a portable, self-describing directory of personal health data serialized as RDF/Turtle files. The Pod structure supports local on-device storage, directory/ZIP export, and upload to a Solid Pod server.

### 14.2 Directory Layout Overview

```
cascade-pod/
    .well-known/
        solid                          # Pod metadata discovery
    profile/
        card.ttl                       # General identity (foaf:Agent)
        health.ttl                     # Health demographics (cascade:PatientProfile)
    settings/
        publicTypeIndex.ttl            # Public type registrations
        privateTypeIndex.ttl           # Private type registrations
    clinical/
        medications.ttl                # health:MedicationRecord
        conditions.ttl                 # health:ConditionRecord
        allergies.ttl                  # health:AllergyRecord
        lab-results.ttl                # health:LabResultRecord
        vital-signs.ttl                # clinical:VitalSign
        immunizations.ttl              # health:ImmunizationRecord
        procedures.ttl                 # clinical:Procedure
        family-history.ttl             # health:FamilyHistoryRecord
        insurance.ttl                  # clinical:CoverageRecord
    wellness/
        heart-rate.ttl                 # health:HeartRateData
        blood-pressure.ttl             # health:BloodPressureData
        activity.ttl                   # health:ActivityData
        sleep.ttl                      # health:SleepData
        supplements.ttl                # clinical:Supplement
    coverage/
        plans/                         # coverage:InsurancePlan (preferred)
    manifest.ttl                       # W3C PROV-O export metadata
```

### 14.3 Type Index Discovery

A conformant Pod reader MUST discover data locations using type indexes rather than hardcoded paths:

1. Read `.well-known/solid` to find the profile URI
2. Read `profile/card.ttl` to find the type index URIs
3. Read `settings/privateTypeIndex.ttl` to find data file locations
4. For each `solid:TypeRegistration`, resolve `solid:instance` or `solid:instanceContainer`

The directory names above are RECOMMENDED defaults, not requirements. A Pod author MAY organize data differently as long as type indexes register the locations.

### 14.4 File Naming Conventions

- **Aggregate files** contain all records of a single type (e.g., `medications.ttl` contains all medication records)
- File names use **lowercase kebab-case** (e.g., `lab-results.ttl`, `heart-rate.ttl`)
- Each aggregate file includes namespace prefix declarations at the top
- Each aggregate file includes a header comment block describing its contents

### 14.5 Reference

For the complete specification including access control (ACL files), export metadata, interoperability requirements, and a full example directory tree, see the [Pod Structure Specification](../pod-structure.md).

---

## Appendix A: Standard Namespace Prefixes

The complete set of namespace prefixes used across Cascade Protocol vocabularies:

| Prefix | Namespace URI | Description |
|---|---|---|
| `cascade:` | `https://ns.cascadeprotocol.org/core/v1#` | Core vocabulary (versioning, provenance, identity, demographics) |
| `health:` | `https://ns.cascadeprotocol.org/health/v1#` | Health & wellness vocabulary (consumer device observations) |
| `clinical:` | `https://ns.cascadeprotocol.org/clinical/v1#` | Clinical document vocabulary (EHR-imported data) |
| `checkup:` | `https://ns.cascadeprotocol.org/checkup/v1#` | Checkup vocabulary (patient-facing summaries, Layer 3) |
| `pots:` | `https://ns.cascadeprotocol.org/pots/v1#` | POTS screening protocol vocabulary |
| `coverage:` | `https://ns.cascadeprotocol.org/coverage/v1#` | Insurance/benefits vocabulary |
| `fhir:` | `http://hl7.org/fhir/` | HL7 FHIR |
| `sct:` | `http://snomed.info/sct/` | SNOMED CT |
| `loinc:` | `http://loinc.org/rdf#` | LOINC (canonical form for this specification) |
| `rxnorm:` | `http://www.nlm.nih.gov/research/umls/rxnorm/` | RxNorm (NLM) |
| `icd10:` | `http://hl7.org/fhir/sid/icd-10-cm/` | ICD-10-CM |
| `ucum:` | `http://unitsofmeasure.org/` | Unified Code for Units of Measure |
| `xsd:` | `http://www.w3.org/2001/XMLSchema#` | XML Schema data types |
| `prov:` | `http://www.w3.org/ns/prov#` | W3C PROV-O provenance ontology |
| `owl:` | `http://www.w3.org/2002/07/owl#` | OWL Web Ontology Language |
| `rdfs:` | `http://www.w3.org/2000/01/rdf-schema#` | RDF Schema |
| `rdf:` | `http://www.w3.org/1999/02/22-rdf-syntax-ns#` | RDF |
| `dct:` | `http://purl.org/dc/terms/` | Dublin Core terms |
| `foaf:` | `http://xmlns.com/foaf/0.1/` | FOAF (Friend of a Friend) |
| `vcard:` | `http://www.w3.org/2006/vcard/ns#` | vCard ontology |
| `sh:` | `http://www.w3.org/ns/shacl#` | SHACL (Shapes Constraint Language) |

---

## Appendix B: LOINC Code Reference

Common LOINC codes used across Cascade Protocol data types.

### Vital Signs

| Metric | LOINC Code | LOINC Name |
|---|---|---|
| Systolic Blood Pressure | `8480-6` | Systolic blood pressure |
| Diastolic Blood Pressure | `8462-4` | Diastolic blood pressure |
| Blood Pressure Panel | `85354-9` | Blood pressure panel |
| Heart Rate | `8867-4` | Heart rate |
| Resting Heart Rate | `40443-4` | Heart rate --resting |
| Walking Heart Rate | `89270-3` | Heart rate --W exercise |
| Respiratory Rate | `9279-1` | Respiratory rate |
| Body Temperature | `8310-5` | Body temperature |
| Oxygen Saturation (SpO2) | `2708-6` | Oxygen saturation |
| HRV (SDNN) | `80404-7` | R-R interval standard deviation (SDNN) |

### Body Measurements

| Metric | LOINC Code | LOINC Name |
|---|---|---|
| Body Weight | `29463-7` | Body weight |
| Body Height | `8302-2` | Body height |
| BMI | `39156-5` | Body mass index |

### Fitness

| Metric | LOINC Code | LOINC Name |
|---|---|---|
| VO2 Max | `60842-2` | VO2 max |

### Activity

| Metric | LOINC Code | LOINC Name |
|---|---|---|
| Steps in 24 hours | `41950-7` | Number of steps in 24 hour Measured |
| Calories Burned | `41981-2` | Calories burned |
| Exercise Activity | `73985-4` | Exercise activity |

### Sleep

| Metric | LOINC Code | LOINC Name |
|---|---|---|
| Sleep Duration | `93832-4` | Sleep duration |

### Common Lab Tests

| Test | LOINC Code | Category |
|---|---|---|
| Hemoglobin A1C | `4548-4` | Metabolic |
| Glucose (fasting) | `1558-6` | Metabolic |
| Glucose (random) | `2345-7` | Metabolic |
| Total Cholesterol | `2093-3` | Lipid |
| HDL Cholesterol | `2085-9` | Lipid |
| LDL Cholesterol | `2089-1` | Lipid |
| Triglycerides | `2571-8` | Lipid |
| TSH | `3016-3` | Thyroid |
| Free T4 | `3024-7` | Thyroid |
| Hemoglobin | `718-7` | Hematology |
| WBC | `6690-2` | Hematology |
| Platelet Count | `777-3` | Hematology |
| Creatinine | `2160-0` | Renal |
| eGFR | `33914-3` | Renal |
| ALT | `1742-6` | Hepatic |
| AST | `1920-8` | Hepatic |

---

## Appendix C: Provenance Classes

The complete provenance class hierarchy defined in `core.ttl`:

```
cascade:DataProvenance (base class, subclass of prov:Entity)
|
+-- cascade:ConsumerGenerated
|   |   Label: Consumer-Generated
|   |   Description: Data from personal devices in non-clinical settings
|   |
|   +-- cascade:DeviceGenerated
|   |       Label: Device-Generated
|   |       Description: Data from consumer health devices
|   |       (Apple Watch, BP cuff, glucose meter)
|   |
|   +-- cascade:SelfReported
|   |       Label: Self-Reported
|   |       Description: Data manually entered by the patient
|   |       (symptom logs, medication adherence, intake forms)
|   |
|   +-- cascade:ConsumerWellness
|           Label: Consumer Wellness
|           Description: Aggregated wellness data from consumer platforms
|           (Apple Health, Google Fit)
|
+-- cascade:ClinicalGenerated
    |   Label: Clinical-Generated
    |   Description: Data from clinical settings under provider supervision
    |
    +-- cascade:EHRVerified
    |       Label: EHR-Verified
    |       Description: Imported from verified EHR systems
    |       (Epic MyChart, Cerner, AllScripts)
    |
    +-- cascade:ScannedDocument
    |       Label: Scanned Document
    |       Description: Extracted from scanned/photographed clinical documents
    |
    +-- cascade:AIExtracted
            Label: AI-Extracted
            Description: Extracted from clinical documents using AI/NLP
```

**Disjointness:** `cascade:ConsumerGenerated` and `cascade:ClinicalGenerated` are declared `owl:disjointWith` each other. Data cannot be both consumer-generated and clinical-generated.

**Provenance in Turtle:**

```turtle
# EHR-imported medication
<urn:uuid:...> cascade:dataProvenance cascade:EHRVerified .

# Patient-entered allergy
<urn:uuid:...> cascade:dataProvenance cascade:SelfReported .

# Apple Watch heart rate
<urn:uuid:...> cascade:dataProvenance cascade:DeviceGenerated .
```

---

## Appendix D: Data Types Covered and Remaining

Phase 2 of this specification now covers all clinical record types, wellness observations, comprehensive provenance, and pod structure conventions. The following items from the original Phase 2 plan are now documented in this specification:

- **Immunizations** -- See Section 8
- **Procedures** -- See Section 9
- **Family History** -- See Section 10
- **Coverage/Insurance** -- See Section 11
- **Wellness Observations** (Heart Rate, Blood Pressure, Activity, Sleep, HRV, VO2 Max, Body Measurements) -- See Section 12
- **Comprehensive Provenance Model** -- See Section 13
- **Pod Structure Conventions** -- See Section 14

### Data Types Deferred to Phase 3

The following data types are not yet covered and will be addressed in subsequent releases:

- **Medication Use Episodes** -- `clinical:MedicationUseEpisode` for longitudinal medication tracking with reconciliation from multiple source records, inferred status, and explainable confidence. The SHACL shape (`clinical:MedicationUseEpisodeShape`) is implemented.
- **Lab Test Series** -- `clinical:LabTestSeries` for longitudinal lab result trending with inferred trend direction and reference range tracking.
- **JSON-LD Context** -- The published `cascade.jsonld` context file for JSON-LD serialization.
- **Metric Trends** -- `health:MetricTrend` for time-bounded wellness trends with direction, magnitude, and confidence. The SHACL shape (`health:MetricTrendShape`) is implemented.

---

## Document History

| Version | Date | Changes |
|---|---|---|
| 1.0 | 2026-02-19 | Initial release. Phase 1 covering 6 data types: Medications, Conditions, Allergies, Lab Results, Vital Signs, Patient Profile. |
| 2.0 | 2026-02-19 | Phase 2 completion. Added 7 new sections: Immunizations (Section 8), Procedures (Section 9), Family History (Section 10), Coverage/Insurance (Section 11), Wellness Observations (Section 12), Comprehensive Provenance Model (Section 13), Pod Structure Conventions (Section 14). Updated Appendix D to reflect completed coverage. |
