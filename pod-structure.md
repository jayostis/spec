# Cascade Protocol Pod Structure Specification

**Status:** Draft
**Version:** 1.1
**Date:** 2026-08-27
**Authors:** Cascade Agentic Labs LLC
**Website:** https://cascadeprotocol.org

---

## Table of Contents

1. [Overview](#1-overview)
2. [Discovery Mechanism](#2-discovery-mechanism)
3. [Required Structure](#3-required-structure)
4. [Standard Data Directories](#4-standard-data-directories)
5. [Domain-Specific Extensions](#5-domain-specific-extensions)
6. [Reserved Namespaces](#6-reserved-namespaces)
7. [File Naming Conventions](#7-file-naming-conventions)
8. [Access Control (.acl files)](#8-access-control-acl-files)
9. [Export Metadata](#9-export-metadata)
10. [Interoperability Requirements](#10-interoperability-requirements)
11. [Appendix A: Complete Example Pod Directory Tree](#appendix-a-complete-example-pod-directory-tree)
12. [Appendix B: Type Index Registration Format](#appendix-b-type-index-registration-format)
13. [Appendix C: Manifest TTL Format](#appendix-c-manifest-ttl-format)
14. [Appendix D: ACL File Templates](#appendix-d-acl-file-templates)

---

## 1. Overview

A Cascade Protocol **Pod** is a portable, self-describing directory of personal health data serialized as RDF/Turtle files. The Pod structure is designed so that health data can be:

- Stored locally on-device with encryption at rest
- Exported as a directory or ZIP archive for sharing
- Uploaded to a Solid Pod server for decentralized storage and access control
- Read by any compliant tool without prior knowledge of the producing application

### 1.1 Relationship to Solid

Cascade Pods follow the [Solid Protocol](https://solidproject.org/TR/protocol) conventions for resource organization, discovery, and access control:

- **WebID-TLS** identity via `profile/card.ttl`
- **Type Indexes** for data discovery (`settings/publicTypeIndex.ttl`, `settings/privateTypeIndex.ttl`)
- **LDP Containers** for resource grouping (`index.ttl` files with `ldp:contains` triples)
- **WAC (Web Access Control)** for authorization (`.acl` files)
- **`.well-known/solid`** for Pod metadata discovery

A Cascade Pod is a valid Solid Pod. Any Solid-compatible tool SHOULD be able to read the structural metadata (profile, type indexes, ACLs) even if it does not understand Cascade Protocol vocabularies.

### 1.2 Design Principles

1. **Discovery over convention.** Tools MUST use type indexes to find data, not hardcoded paths. Directory names are human-readable hints, not a contract.
2. **Graceful ignorance.** A tool encountering an unknown directory (e.g., `/diabetes/`) MUST NOT error. It MUST ignore what it does not understand.
3. **Extension without coordination.** Domain-specific applications can add directories to a Pod following the naming conventions in this specification. No central registry is required.
4. **Minimum viable Pod.** A valid Pod can contain as little as three files. Applications MUST NOT require the full directory tree to be present.
5. **ACLs are optional but recommended.** Local-only Pods MAY omit ACL files. Pods intended for export or upload to a Solid server SHOULD include them.
6. **Provenance is first-class.** Every Pod export SHOULD include a manifest with W3C PROV-O metadata describing when, how, and by what software the Pod was generated.

### 1.3 Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119).

| Term | Definition |
|------|-----------|
| **Pod** | A self-contained directory tree of RDF resources conforming to this specification |
| **Container** | A directory within a Pod that groups related resources, represented as an LDP Container |
| **Resource** | A single Turtle (.ttl) file containing RDF triples |
| **Namespace** | A top-level directory in a Pod corresponding to a data domain (e.g., `clinical/`, `wellness/`) |
| **Type Index** | A Solid Type Index document that maps RDF classes to their storage locations within the Pod |
| **Aggregate file** | A Turtle file containing all records of a single type (e.g., `medications.ttl` contains all medication records) |

---

## 2. Discovery Mechanism

### 2.1 Discovery Flow

A conformant Pod reader MUST discover data locations using the following sequence:

```
1. Read .well-known/solid
      |
      v
2. Resolve profile URI --> profile/card.ttl
      |
      v
3. Follow solid:publicTypeIndex --> settings/publicTypeIndex.ttl
   Follow solid:privateTypeIndex --> settings/privateTypeIndex.ttl
      |
      v
4. For each solid:TypeRegistration, resolve solid:instance
   or solid:instanceContainer to locate data files
```

### 2.2 Why Not Hardcoded Paths?

A conformant reader MUST NOT assume that clinical data lives at `/clinical/medications.ttl`. A Pod author MAY organize data in any directory structure and register the locations via type indexes. The directory names in this specification are RECOMMENDED defaults, not requirements.

This ensures that:
- A Pod can be reorganized without breaking readers
- Multiple applications can contribute data to the same Pod without path conflicts
- Future versions of this specification can change default paths without breaking existing Pods

### 2.3 Fallback Behavior

If a reader cannot locate a type index (e.g., `settings/publicTypeIndex.ttl` is missing), it MAY fall back to scanning the root `index.ttl` for `ldp:contains` triples and inspecting container contents. This is a best-effort fallback and SHOULD NOT be relied upon as the primary discovery mechanism.

---

## 3. Required Structure

### 3.1 .well-known/solid

**Path:** `/.well-known/solid`
**Format:** JSON-LD
**Status:** REQUIRED

The `.well-known/solid` file is the entry point for Pod discovery. A Solid client resolving a Pod URL fetches this file first to locate the profile document, storage root, and type indexes.

```json
{
  "@context": "https://www.w3.org/ns/solid/terms",
  "pod_root": "/",
  "profile": "/profile/card.ttl#me",
  "storage": "/",
  "publicTypeIndex": "/settings/publicTypeIndex.ttl",
  "privateTypeIndex": "/settings/privateTypeIndex.ttl"
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `@context` | URI | MUST be `https://www.w3.org/ns/solid/terms` |
| `pod_root` | Path | Root path of the Pod. MUST be `"/"` for standalone Pods |
| `profile` | URI | Path to the WebID profile document, including fragment identifier |
| `storage` | Path | Root storage container. MUST be `"/"` for standalone Pods |
| `publicTypeIndex` | Path | Path to the public type index document |
| `privateTypeIndex` | Path | Path to the private type index document |

### 3.2 profile/card.ttl

**Path:** `/profile/card.ttl`
**Format:** Turtle (RDF)
**Status:** REQUIRED

The WebID profile card identifies the Pod owner and links to discovery resources. The `<#me>` fragment identifier serves as the WebID.

```turtle
@prefix foaf: <http://xmlns.com/foaf/0.1/> .
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix pim: <http://www.w3.org/ns/pim/space#> .

<#me>
    a foaf:Person ;
    foaf:name "Cascade Protocol User" ;
    solid:publicTypeIndex </settings/publicTypeIndex.ttl> ;
    solid:privateTypeIndex </settings/privateTypeIndex.ttl> ;
    pim:storage </> .
```

**Required triples for `<#me>`:**

| Predicate | Object | Notes |
|-----------|--------|-------|
| `a` | `foaf:Person` | REQUIRED |
| `solid:publicTypeIndex` | URI | REQUIRED. Path to the public type index |
| `solid:privateTypeIndex` | URI | REQUIRED. Path to the private type index |
| `pim:storage` | URI | REQUIRED. Root storage container |

**Optional triples:**

| Predicate | Object | Notes |
|-----------|--------|-------|
| `foaf:name` | Literal | RECOMMENDED. Display name for the Pod owner |
| `cascade:potsTestContainer` | URI | Domain-specific pointer (POTS Check app) |

A Pod exporter SHOULD use a generic display name (e.g., `"Cascade Protocol User"`) rather than the patient's real name in the profile card, unless the user has explicitly consented to include identifying information. The profile card is intended for Solid server identity, not as a clinical demographics record.

### 3.3 settings/publicTypeIndex.ttl

**Path:** `/settings/publicTypeIndex.ttl`
**Format:** Turtle (RDF)
**Status:** REQUIRED

The public type index registers data locations that are visible to other authenticated agents. Each registration maps an RDF class to its storage location within the Pod.

```turtle
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix health: <https://ns.cascadeprotocol.org/health/v1#> .
@prefix clinical: <https://ns.cascadeprotocol.org/clinical/v1#> .
@prefix dct: <http://purl.org/dc/terms/> .

<#medications>
    a solid:TypeRegistration ;
    solid:forClass clinical:MedicationRecord ;
    solid:instance </clinical/medications.ttl> ;
    dct:title "Medication Records" .

<#conditions>
    a solid:TypeRegistration ;
    solid:forClass clinical:ConditionRecord ;
    solid:instance </clinical/conditions.ttl> ;
    dct:title "Condition Records" .

<#heart-rate>
    a solid:TypeRegistration ;
    solid:forClass health:HeartRateStatistics ;
    solid:instance </wellness/heart-rate.ttl> ;
    dct:title "Heart Rate Data" .
```

See [Appendix B](#appendix-b-type-index-registration-format) for the complete registration format and all standard registrations.

### 3.4 settings/privateTypeIndex.ttl

**Path:** `/settings/privateTypeIndex.ttl`
**Format:** Turtle (RDF)
**Status:** REQUIRED

The private type index registers data locations visible only to the Pod owner. This is appropriate for sensitive data that the user does not wish to share via type index discovery.

```turtle
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix dct: <http://purl.org/dc/terms/> .

<#all-health-data>
    a solid:TypeRegistration ;
    solid:forClass cascade:HealthData ;
    solid:instance </> ;
    dct:title "All Health Data" ;
    dct:description "Complete health data from this Pod" .
```

**Guidance on public vs. private registrations:**

- Data types the user wishes to make discoverable to authorized agents (e.g., medications for a healthcare provider) SHOULD be registered in the public type index.
- Broad, catch-all registrations and sensitive data types SHOULD be registered in the private type index.
- A data type MAY appear in both indexes with different access scopes.

### 3.5 index.ttl (Root LDP Container)

**Path:** `/index.ttl`
**Format:** Turtle (RDF)
**Status:** RECOMMENDED

The root container index declares the Pod as an LDP BasicContainer and lists all top-level containers using `ldp:contains` triples. This enables clients to enumerate the Pod's top-level structure.

```turtle
@prefix ldp: <http://www.w3.org/ns/ldp#> .
@prefix dct: <http://purl.org/dc/terms/> .

<./>
    a ldp:Container, ldp:BasicContainer ;
    dct:title "Pod Root Container" ;
    ldp:contains
        </profile/>,
        </settings/>,
        </clinical/>,
        </wellness/> .
```

The `ldp:contains` list MUST include all top-level directories present in the Pod. When new namespaces are added to a Pod, the root `index.ttl` MUST be updated to include them.

---

## 4. Standard Data Directories

The following directories are the RECOMMENDED defaults for organizing health data. Tools MUST use type index discovery rather than relying on these paths, but Pod exporters SHOULD use these paths unless there is a specific reason to deviate.

### 4.1 clinical/ -- Clinical Data

**Path:** `/clinical/`
**Vocabulary:** `clinical:` (`https://ns.cascadeprotocol.org/clinical/v1#`)
**Description:** Provider-generated clinical data imported from Electronic Health Records (EHRs), Apple Health clinical records, or manually entered by users with clinical provenance.

**Standard aggregate files:**

| File | RDF Class | Description |
|------|-----------|-------------|
| `medications.ttl` | `clinical:MedicationRecord` | Active and historical medications with dosages |
| `conditions.ttl` | `clinical:ConditionRecord` | Diagnosed medical conditions |
| `allergies.ttl` | `clinical:AllergyRecord` | Allergies and adverse reactions |
| `lab-results.ttl` | `clinical:LabResult` | Laboratory test results with reference ranges |
| `immunizations.ttl` | `clinical:ImmunizationRecord` | Vaccination records |
| `vital-signs.ttl` | `clinical:VitalSign` | Clinical vital sign measurements and trends |
| `patient-profile.ttl` | `cascade:PatientProfile` | Demographics, contact information |
| `insurance.ttl` | `coverage:InsurancePlan` | Insurance plan details |
| `procedures.ttl` | `clinical:Procedure` | Medical procedures |
| `family-history.ttl` | `clinical:FamilyHistoryRecord` | Family medical history |
| `screenings.ttl` | `clinical:ScreeningResult` | Health screening results |
| `diagnostic-results.ttl` | `clinical:DiagnosticResult` | Diagnostic test results |

Each file contains all records of its type as an aggregate. For example, `medications.ttl` contains all medication records in a single file, not one file per medication.

### 4.2 wellness/ -- Wellness/Device Data

**Path:** `/wellness/`
**Vocabulary:** `health:` (`https://ns.cascadeprotocol.org/health/v1#`)
**Description:** Consumer-generated wellness data from wearable devices (Apple Watch, Fitbit, etc.), self-tracking apps, and manual user entries. This data carries consumer-generated provenance and is classified as non-diagnostic.

**Standard aggregate files:**

| File | RDF Class | Description |
|------|-----------|-------------|
| `heart-rate.ttl` | `health:HeartRateStatistics` | Resting and walking heart rate history |
| `blood-pressure.ttl` | `health:BPStatistics` | Blood pressure readings and history |
| `activity.ttl` | `health:ActivitySnapshot` | Daily activity summaries (steps, calories, exercise) |
| `sleep.ttl` | `health:SleepStatistics` | Sleep duration and quality statistics |
| `hrv.ttl` | `health:HRVStatistics` | Heart rate variability data |
| `body-measurements.ttl` | `health:BodyMeasurement` | VO2 max, body mass, height, temperature, SpO2, glucose |
| `supplements.ttl` | `health:Supplement` | Supplement and vitamin tracking |

**Nested container pattern (for per-record storage):**

When individual records need to be stored separately (e.g., for Solid server compatibility where each resource has its own URI), the wellness directory MAY use nested containers:

```
wellness/
  diagnostics/
    pots-checks/
      index.ttl
      test-2026-01-15T10-30-00Z.ttl
      test-2026-02-01T14-15-00Z.ttl
```

This nested pattern is used by POTS Check for individual test results that need their own URIs and access control.

### 4.3 attachments/ -- Content-Addressed Binary Storage

**Path:** `/attachments/`
**Vocabulary:** `cascade:` (`https://ns.cascadeprotocol.org/core/v1#`), core v3.7
**Status:** OPTIONAL. A Pod with no binary documents has no `attachments/` directory, and a reader MUST treat its absence as "no attachments", never as an error.

Clinical records routinely point at a document that is not RDF: the PDF a `DiagnosticReport` was rendered as, the scanned page behind a `DocumentReference`. This directory is where those bytes live.

**The bytes are files, not literals.** FHIR permits either, through `Attachment.data` (inline base64) or `Attachment.url`. A Pod takes the second, because a Pod is not a message: every consumer parses the Turtle files in full to answer any question, so an unbounded base64 literal is paid for by readers that will never look at the attachment. The Turtle carries a small metadata node and the bytes are an ordinary file.

#### Layout

```
attachments/
  sha-256/
    3f786850e387550fdab836ed7e6dc881de23001b1f6d1a3f...
    a94a8fe5ccb19ba61c4c0873d391e987982fbbd3b8b5f1e9...
  .acl
```

```
attachments/{algorithm}/{digest}
```

- `{algorithm}` is the token from the [IANA Named Information Hash Algorithm Registry](https://www.rfc-editor.org/rfc/rfc6920) that the digest was computed with. New implementations MUST write `sha-256`. The algorithm is a directory level rather than a filename prefix so that adopting a stronger hash is a new directory, not a re-parse of every name.
- `{digest}` is the digest of the file's own bytes, lowercase hexadecimal, with **no extension**. The media type is stated in RDF; a media type in a filename is a second claim about the same bytes that nothing verifies.

**The file's name IS its digest**, which is what makes the store checkable: a consumer hashes what it read and compares it with where it read it from, and nothing has to be trusted to keep name and content in agreement. Two consequences follow with no mechanism behind them: the same document arriving from two sources is stored once, and re-importing is idempotent without a deduplication pass.

Writers MUST NOT write a file here whose name is not the digest of its contents. Readers SHOULD verify a digest before relying on an attachment, and MUST treat a mismatch as a missing attachment rather than as the document the metadata describes.

#### The metadata node

Each stored file is described by a `cascade:Attachment` in the Turtle of whichever container references it, and is linked from the record it renders with `cascade:hasAttachment`:

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .

<#report-2026-03-04>
    cascade:hasAttachment <#attachment-3f786850> .

<#attachment-3f786850>
    a cascade:Attachment ;
    cascade:attachmentPath "attachments/sha-256/3f786850e387550fdab836ed7e6dc881de23001b1f6d1a3f" ;
    cascade:contentHash "3f786850e387550fdab836ed7e6dc881de23001b1f6d1a3f" ;
    cascade:hashAlgorithm "sha-256" ;
    cascade:attachmentMediaType "application/pdf" ;
    cascade:byteSize 148213 ;
    cascade:attachmentTitle "Complete Blood Count -- Final Report" .
```

`cascade:attachmentPath` MUST be relative to the Pod root. An absolute path or a URL breaks the moment a Pod is copied or re-rooted, which Pods routinely are, and a `..` segment makes an attachment reference a way to read a file the Pod does not contain. `cascade:AttachmentShape` in `core.shapes.ttl` rejects all three.

#### Deliberately implementation-defined in this release

Two questions are named here so that their absence is a decision and not an oversight:

- **Encryption at rest.** An implementation MAY encrypt attachment files by whatever means it already encrypts a Pod. This specification states nothing about the mechanism, so nothing here has to be revised when one is ratified.
- **Sync.** How an `attachments/` directory participates in Pod synchronization is unspecified. Content addressing makes the naive answer safe in one direction (a file's content never changes under its name), which is why deferring the rest is tolerable.

---

## 5. Domain-Specific Extensions

### 5.1 Extension Pattern

The Cascade Protocol is designed to be extended by domain-specific applications. Any application MAY add its own top-level directory to a Pod, provided it follows these rules:

1. The directory name MUST be a lowercase, hyphen-separated identifier (e.g., `visit-prep`, `adherence`).
2. The directory MUST be registered in a type index so that other tools can discover it.
3. The directory MUST be listed in the root `index.ttl` container.
4. Files within the directory MUST use the `.ttl` extension for Turtle resources.
5. The directory SHOULD include an `index.ttl` file listing its contents as an LDP Container.

Applications reading a Pod MUST ignore directories they do not recognize. An application that understands only `clinical/` and `wellness/` MUST NOT error or warn when encountering `adherence/`, `visit-prep/`, or any other unknown directory.

### 5.2 Examples

**Cascade Checkup** adds these domain-specific directories:

```
adherence/
  daily-check-ins.ttl        # checkup:DailyCheckIn instances

visit-prep/
  discussion-topics.ttl      # checkup:DiscussionTopic instances
  visit-prep-notes.ttl       # checkup:VisitPrepNotes
  visit-issues.ttl           # checkup:VisitIssue instances
  suggested-questions.ttl    # checkup:SuggestedQuestion instances
```

**POTS Check** uses a nested wellness container:

```
wellness/
  diagnostics/
    pots-checks/
      index.ttl               # LDP Container listing test results
      test-{id}.ttl            # Individual pots:POTSTest results
```

**Cascade Workbench** adds these directories (vocabulary: `workbench/v1-draft`):

```
notes/
  {id}.ttl                    # oa:Annotation resources: user-authored notes,
                              # research flags, and follow-ups over records,
                              # claims, or investigations (workbench v1-draft.0.5;
                              # W3C Web Annotation + PROV-O attribution; follow-ups
                              # dual-typed cal:Vtodo with ical:due / ical:status)

annotations/
  {id}.ttl                    # workbench: append-only record-amendment overlays
                              # (Amendment / Annotation / Retraction / Tombstone)
                              # -- edit machinery, deliberately separate from the
                              # user-authored content in notes/
```

**Hypothetical diabetes management app:**

```
diabetes/
  glucose-readings.ttl        # diabetes:GlucoseReading instances
  insulin-doses.ttl           # diabetes:InsulinDose instances
  carb-entries.ttl            # diabetes:CarbEntry instances
  pump-settings.ttl           # diabetes:PumpSettings
```

A Cascade Checkup reader encountering a Pod with `/diabetes/` would simply ignore that directory. A diabetes app encountering `/visit-prep/` would do the same.

---

## 6. Reserved Namespaces

The following namespace directories are reserved for future Cascade Protocol features. Applications MUST NOT use these directory names for other purposes. The directories are defined in the SDK's `PodNamespace` enum but are not yet implemented in any shipping application.

| Directory | Purpose | Status |
|-----------|---------|--------|
| `consents/` | ODRL consent policies governing data sharing | RESERVED |
| `acl/` | WAC/ACL authorization rules (centralized ACL store) | RESERVED |
| `profiles/` | WebID identity cards (multi-identity support) | RESERVED |
| `shares/` | ShareManifest resources for tracking shared data | RESERVED |
| `provenance/` | PROV-O audit trail and access receipts | RESERVED |
| `context/` | JSON-LD context definitions for vocabulary resolution | RESERVED |
| `shapes/` | SHACL validation shapes for data quality enforcement | RESERVED |

Applications MAY create these directories for experimental use, but MUST NOT rely on their structure being stable until the corresponding specification is finalized.

---

## 7. File Naming Conventions

### 7.1 Aggregate Files ({data-type}.ttl)

The default pattern for data storage is one aggregate file per data type within a namespace directory:

```
{namespace}/{data-type}.ttl
```

**Examples:**
- `clinical/medications.ttl` -- all medication records
- `wellness/heart-rate.ttl` -- all heart rate observations
- `adherence/daily-check-ins.ttl` -- all daily check-in records

The data-type portion of the filename MUST be lowercase and hyphen-separated. It SHOULD match the RDF class name in lowercase-hyphenated form (e.g., `MedicationRecord` becomes `medications.ttl`, `HeartRateStatistics` becomes `heart-rate.ttl`).

### 7.2 Individual Records ({id}.ttl)

When data needs per-record granularity (e.g., for individual access control or Solid server resource creation), records MAY be stored as individual files:

```
{namespace}/{sub-container}/{id}.ttl
```

**Examples:**
- `wellness/diagnostics/pots-checks/test-2026-01-15T10-30-00Z.ttl`
- `clinical/lab-results/result-abc123.ttl`

Individual record filenames SHOULD include a human-readable prefix and a unique identifier (UUID, timestamp, or domain-specific ID). Filenames MUST NOT contain spaces or characters outside the set `[a-zA-Z0-9._-]`.

### 7.3 Dated Resource Paths

For time-series data with large volumes, a dated directory structure MAY be used:

```
{namespace}/{sub-container}/{YYYY}/{MM}/{filename}.ttl
```

**Example:**
- `wellness/diagnostics/pots-checks/2026/01/test-result-abc123.ttl`

This pattern is supported by the SDK's `PodNamespace.datedResourcePath()` method and is RECOMMENDED for containers expected to hold more than 100 individual records.

### 7.4 Container Indexes (index.ttl)

Any directory acting as an LDP Container SHOULD include an `index.ttl` file that declares its contents:

```turtle
@prefix ldp: <http://www.w3.org/ns/ldp#> .
@prefix dct: <http://purl.org/dc/terms/> .
@prefix pots: <https://ns.cascadeprotocol.org/pots/v1#> .

<./>
    a ldp:Container ;
    dct:title "POTS Test Results" ;
    dct:description "NASA Lean Test results for POTS screening" ;
    ldp:contains
        <test-2026-01-15.ttl>,
        <test-2026-02-01.ttl> .
```

Container index files are RECOMMENDED for directories containing individual records. They are REQUIRED for the Pod root (`/index.ttl`).

### 7.5 Attachment Files (Content-Addressed)

Files under `attachments/` are the one place in a Pod where the filename is not chosen. It is the digest of the file's own bytes, in lowercase hexadecimal, with no extension:

```
attachments/{algorithm}/{digest}
```

This is a deliberate exception to sections 7.1 and 7.2, and the reason is that the name is a claim the bytes can be checked against. A descriptive name, or an extension, would be a second claim about the same file that nothing verifies. Everything a human or a renderer needs to know about the file (its media type, its title, its size) is stated in RDF on the `cascade:Attachment` node that points at it. See section 4.3.

### 7.6 SHACL Shapes Files

SHACL validation shapes files SHOULD follow the naming convention `{vocabulary}.shapes.ttl`:

```
shapes/clinical.shapes.ttl
shapes/health.shapes.ttl
shapes/checkup.shapes.ttl
```

> **Resolved:** The Checkup SHACL shapes file has been renamed from `checkup-adult.shapes.ttl` to `checkup.shapes.ttl` to follow the `{vocabulary}.shapes.ttl` convention (ISSUE-3, resolved 2026-02-19).

---

## 8. Access Control (.acl files)

Cascade Pods use [Web Access Control (WAC)](https://solidproject.org/TR/wac) for authorization. ACL files define who can read, write, and control resources within the Pod.

### 8.1 Root ACL

**Path:** `/.acl`
**Status:** RECOMMENDED for exported Pods

The root ACL grants the Pod owner full control over the entire Pod. It uses `acl:default` to apply to all resources that do not have their own ACL.

```turtle
@prefix acl: <http://www.w3.org/ns/auth/acl#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

# Owner has full control
<#owner>
    a acl:Authorization ;
    acl:agent <https://example.org/profile/card#me> ;
    acl:accessTo <./> ;
    acl:default <./> ;
    acl:mode acl:Read, acl:Write, acl:Control .
```

The `acl:default` triple means this ACL applies to all resources within the container (and sub-containers) unless overridden by a more specific ACL.

### 8.2 Per-Container ACLs

**Path:** `/{namespace}/.acl`
**Status:** RECOMMENDED for exported Pods

Each top-level data directory SHOULD have its own ACL file. By default, these grant owner-only access with the same pattern as the root ACL:

```turtle
@prefix acl: <http://www.w3.org/ns/auth/acl#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

<#owner>
    a acl:Authorization ;
    acl:agent <https://example.org/profile/card#me> ;
    acl:accessTo <./> ;
    acl:default <./> ;
    acl:mode acl:Read, acl:Write, acl:Control .
```

Per-container ACLs are generated for each unique top-level directory derived from the Pod's containers. For a Pod with `clinical/` and `wellness/`, this means:

- `/clinical/.acl`
- `/wellness/.acl`

Per-container ACLs enable granular sharing. For example, a user could grant a healthcare provider read access to `/clinical/` while keeping `/wellness/` owner-only.

`/attachments/` is a top-level directory under this rule and SHOULD carry its own ACL. Note that granting read access to `/clinical/` while withholding it from `/attachments/` leaves the recipient with records that reference documents they cannot open; granting the reverse exposes the documents themselves, which routinely contain more identifying detail than the record that points at them. Neither is wrong, but the pairing is a decision and not a default.

### 8.3 Profile ACL (Public Read)

**Path:** `/profile/.acl`
**Status:** RECOMMENDED for exported Pods

The profile directory has a special ACL that grants authenticated agents read access to the WebID profile card. This is necessary for Solid server identity verification.

```turtle
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<#owner>
    a acl:Authorization ;
    acl:agent <https://example.org/profile/card#me> ;
    acl:accessTo <./card.ttl> ;
    acl:mode acl:Read, acl:Write, acl:Control .

<#public>
    a acl:Authorization ;
    acl:agentClass acl:AuthenticatedAgent ;
    acl:accessTo <./card.ttl> ;
    acl:mode acl:Read .
```

Note that the `<#public>` authorization uses `acl:AuthenticatedAgent` rather than `foaf:Agent`. This means only agents with a valid WebID can read the profile -- unauthenticated (anonymous) access is not granted.

### 8.4 Settings ACL

**Path:** `/settings/.acl`
**Status:** RECOMMENDED for exported Pods

The settings directory uses an owner-only ACL. Type index documents are sensitive because they reveal what data exists in the Pod, even if the data itself has separate access controls.

### 8.5 ACL Generation Rules

When an exporter generates ACL files:

1. A root `.acl` MUST be created if any ACL files are generated.
2. A `profile/.acl` MUST use the public-read pattern (Section 8.3).
3. A `settings/.acl` MUST use the owner-only pattern.
4. Each unique top-level data directory SHOULD have an owner-only `.acl`.
5. The `ownerWebID` used in ACL files MUST match the `<#me>` identity in `profile/card.ttl`.

ACL files are OPTIONAL for local-only Pods that will never be uploaded to a server. They are RECOMMENDED for any Pod that will be exported or shared.

---

## 9. Export Metadata

### 9.1 manifest.ttl Structure

**Path:** `/manifest.ttl`
**Format:** Turtle (RDF)
**Status:** RECOMMENDED

The manifest file provides machine-readable metadata about the Pod export, including provenance, versioning, and content summary. It uses the W3C PROV-O ontology for provenance tracking.

```turtle
@prefix prov: <http://www.w3.org/ns/prov#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix dct: <http://purl.org/dc/terms/> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

<#manifest> a cascade:ExportManifest ;
    dct:title "Cascade Checkup Export" ;
    dct:created "2026-02-19T10:00:00Z"^^xsd:dateTime ;
    cascade:schemaVersion "1.3" ;
    cascade:exportFormat "solidPod" ;
    cascade:containerCount "15"^^xsd:integer ;
    cascade:totalRecords "142"^^xsd:integer ;
    cascade:includedCategories "12"^^xsd:integer ;
    prov:wasGeneratedBy [
        a prov:Activity ;
        prov:startedAtTime "2026-02-19T10:00:00Z"^^xsd:dateTime ;
        prov:wasAssociatedWith [
            a prov:SoftwareAgent ;
            rdfs:label "Cascade Checkup" ;
            cascade:exporterVersion "1.0"
        ]
    ] .
```

### 9.2 Manifest Properties

| Property | Type | Description |
|----------|------|-------------|
| `dct:title` | Literal | Human-readable name of the export |
| `dct:created` | `xsd:dateTime` | ISO 8601 timestamp of when the export was generated |
| `cascade:schemaVersion` | Literal | Version of the Cascade Protocol schema used |
| `cascade:exportFormat` | Literal | Export format identifier. `"solidPod"` for Pod exports, `"directory"` for uncompressed directory exports |
| `cascade:containerCount` | `xsd:integer` | Number of non-empty resource files in the export |
| `cascade:totalRecords` | `xsd:integer` | Total number of individual data records across all containers |
| `cascade:includedCategories` | `xsd:integer` | Number of PHI categories included (consent-gated) |
| `prov:wasGeneratedBy` | Blank node | PROV-O Activity describing the export process |

### 9.3 Export Provenance

The `prov:wasGeneratedBy` block records:
- **When:** `prov:startedAtTime` with an ISO 8601 timestamp
- **What:** `prov:wasAssociatedWith` linking to a `prov:SoftwareAgent` that identifies the exporting application and version

This provenance chain ensures that any recipient of a Pod export can determine which application produced it and when, without relying on filesystem metadata.

---

## 10. Interoperability Requirements

### 10.1 Unknown Directories MUST Be Ignored

A conformant Pod reader that encounters a directory it does not recognize MUST silently ignore it. This is the fundamental extensibility guarantee of the Cascade Pod structure.

**Example:** A tool that understands only `clinical/` and `wellness/` receives a Pod containing:

```
clinical/
wellness/
adherence/
visit-prep/
diabetes/
```

The tool MUST process `clinical/` and `wellness/` normally and MUST NOT error, warn, or log diagnostics for `adherence/`, `visit-prep/`, or `diabetes/`.

### 10.2 Type Index SHOULD Be Used for Discovery

A conformant Pod reader SHOULD use type indexes as the primary discovery mechanism. Readers SHOULD NOT assume that a particular RDF class is stored at a specific hardcoded path.

**Correct approach:**

```
1. Read settings/publicTypeIndex.ttl
2. Find: <#medications> solid:forClass clinical:MedicationRecord ;
                        solid:instance </clinical/medications.ttl> .
3. Fetch /clinical/medications.ttl
```

**Incorrect approach:**

```
1. Directly fetch /clinical/medications.ttl (hardcoded path)
```

### 10.3 Minimum Viable Pod

The smallest valid Cascade Pod consists of three files:

```
.well-known/
  solid                          # Pod metadata (JSON-LD)
profile/
  card.ttl                       # WebID profile card
settings/
  publicTypeIndex.ttl            # Public type index (may be empty)
```

A `privateTypeIndex.ttl` is REQUIRED by this specification but MAY be an empty Turtle document (containing only prefix declarations or no triples). The root `index.ttl` is RECOMMENDED but not required for a minimum viable Pod.

Any Pod reader MUST be able to process a minimum viable Pod without error, even though it contains no health data.

### 10.4 Partial Exports

A Pod export MAY include structural containers (empty directories) for namespaces that have no data. This preserves the expected Pod shape for tools that check directory existence. The `PodContainer.isStructural` flag in the SDK supports this pattern.

For example, a Pod with only clinical data might still include an empty `wellness/` directory to signal that the namespace is recognized but currently unpopulated.

### 10.5 Pod Versioning

The Pod structure itself is versioned implicitly through the `cascade:schemaVersion` property in `manifest.ttl`. Readers SHOULD check this version and MAY refuse to process Pods with an unrecognized schema version.

The current schema version is `"1.3"`.

Future versions of this specification will maintain backward compatibility: new directories and file types MAY be added, but existing paths and formats MUST NOT change their semantics.

---

## Appendix A: Complete Example Pod Directory Tree

The following shows a fully-populated Pod export from Cascade Checkup, including all optional elements:

```
CascadeCheckup-Export-20260219T100000Z/
|
|-- .well-known/
|   |-- solid                           # Pod discovery metadata (JSON-LD)
|
|-- .acl                                # Root ACL (owner-only)
|
|-- profile/
|   |-- card.ttl                        # WebID profile card
|   |-- .acl                            # Profile ACL (public read for card.ttl)
|
|-- settings/
|   |-- publicTypeIndex.ttl             # Public type registrations
|   |-- privateTypeIndex.ttl            # Private type registrations
|   |-- .acl                            # Settings ACL (owner-only)
|
|-- clinical/
|   |-- medications.ttl                 # clinical:MedicationRecord
|   |-- conditions.ttl                  # clinical:ConditionRecord
|   |-- allergies.ttl                   # clinical:AllergyRecord
|   |-- lab-results.ttl                 # clinical:LabResult
|   |-- immunizations.ttl               # clinical:ImmunizationRecord
|   |-- vital-signs.ttl                 # clinical:VitalSign
|   |-- patient-profile.ttl             # cascade:PatientProfile
|   |-- insurance.ttl                   # coverage:InsurancePlan
|   |-- family-history.ttl              # clinical:FamilyHistoryRecord
|   |-- screenings.ttl                  # clinical:ScreeningResult
|   |-- diagnostic-results.ttl          # clinical:DiagnosticResult
|   |-- .acl                            # Container ACL (owner-only)
|
|-- wellness/
|   |-- heart-rate.ttl                  # health:HeartRateStatistics
|   |-- blood-pressure.ttl              # health:BPStatistics
|   |-- activity.ttl                    # health:ActivitySnapshot
|   |-- sleep.ttl                       # health:SleepStatistics
|   |-- hrv.ttl                         # health:HRVStatistics
|   |-- body-measurements.ttl           # health:BodyMeasurement
|   |-- supplements.ttl                 # health:Supplement
|   |-- .acl                            # Container ACL (owner-only)
|
|-- adherence/
|   |-- daily-check-ins.ttl             # checkup:DailyCheckIn
|   |-- .acl                            # Container ACL (owner-only)
|
|-- visit-prep/
|   |-- discussion-topics.ttl           # checkup:DiscussionTopic
|   |-- visit-prep-notes.ttl            # checkup:VisitPrepNotes
|   |-- visit-issues.ttl                # checkup:VisitIssue
|   |-- suggested-questions.ttl         # checkup:SuggestedQuestion
|   |-- .acl                            # Container ACL (owner-only)
|
|-- attachments/                        # Content-addressed binary documents
|   |-- sha-256/
|   |   |-- 3f786850e387550fdab836ed...  # Bytes; filename IS the digest
|   |   |-- a94a8fe5ccb19ba61c4c0873...
|   |-- .acl                            # Container ACL (owner-only)
|
|-- index.ttl                           # Root LDP container listing
|-- manifest.ttl                        # Export provenance metadata
|-- README.md                           # Human-readable documentation
```

A POTS Check Pod would look different:

```
Cascade-Pod-Export-20260219T100000Z/
|
|-- .well-known/
|   |-- solid
|
|-- .acl
|
|-- profile/
|   |-- card.ttl
|   |-- .acl
|
|-- settings/
|   |-- publicTypeIndex.ttl
|   |-- privateTypeIndex.ttl
|   |-- .acl
|
|-- wellness/
|   |-- diagnostics/
|   |   |-- pots-checks/
|   |   |   |-- index.ttl               # LDP Container listing test files
|   |   |   |-- test-20260115T103000Z.ttl
|   |   |   |-- test-20260201T141500Z.ttl
|   |   |   |-- .acl
|   |   |-- .acl
|   |-- .acl
|
|-- README.md
```

---

## Appendix B: Type Index Registration Format

### B.1 Registration Structure

Each type registration in a type index follows this pattern:

```turtle
<#{fragment-id}>
    a solid:TypeRegistration ;
    solid:forClass {vocabulary}:{ClassName} ;
    solid:instance </{path}/{file}.ttl> ;
    dct:title "{Human-readable title}" ;
    dct:description "{Optional description}" .
```

**Properties:**

| Property | Status | Description |
|----------|--------|-------------|
| `a solid:TypeRegistration` | REQUIRED | Declares this as a type registration |
| `solid:forClass` | REQUIRED | The RDF class being registered |
| `solid:instance` | REQUIRED* | Path to a specific resource file |
| `solid:instanceContainer` | REQUIRED* | Path to a container holding instances |
| `dct:title` | RECOMMENDED | Human-readable title |
| `dct:description` | OPTIONAL | Longer description |

*One of `solid:instance` or `solid:instanceContainer` MUST be present. Use `solid:instance` for aggregate files (one file containing all records) and `solid:instanceContainer` for directories containing individual record files.

### B.2 Standard Clinical Registrations

```turtle
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix clinical: <https://ns.cascadeprotocol.org/clinical/v1#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix coverage: <https://ns.cascadeprotocol.org/coverage/v1#> .
@prefix dct: <http://purl.org/dc/terms/> .

<#medications>
    a solid:TypeRegistration ;
    solid:forClass clinical:MedicationRecord ;
    solid:instance </clinical/medications.ttl> ;
    dct:title "Medication Records" .

<#conditions>
    a solid:TypeRegistration ;
    solid:forClass clinical:ConditionRecord ;
    solid:instance </clinical/conditions.ttl> ;
    dct:title "Condition Records" .

<#allergies>
    a solid:TypeRegistration ;
    solid:forClass clinical:AllergyRecord ;
    solid:instance </clinical/allergies.ttl> ;
    dct:title "Allergy Records" .

<#lab-results>
    a solid:TypeRegistration ;
    solid:forClass clinical:LabResult ;
    solid:instance </clinical/lab-results.ttl> ;
    dct:title "Lab Results" .

<#immunizations>
    a solid:TypeRegistration ;
    solid:forClass clinical:ImmunizationRecord ;
    solid:instance </clinical/immunizations.ttl> ;
    dct:title "Immunization Records" .

<#vital-signs>
    a solid:TypeRegistration ;
    solid:forClass clinical:VitalSign ;
    solid:instance </clinical/vital-signs.ttl> ;
    dct:title "Vital Signs" .

<#patient-profile>
    a solid:TypeRegistration ;
    solid:forClass cascade:PatientProfile ;
    solid:instance </clinical/patient-profile.ttl> ;
    dct:title "Patient Profile" .

<#insurance>
    a solid:TypeRegistration ;
    solid:forClass coverage:InsurancePlan ;
    solid:instance </clinical/insurance.ttl> ;
    dct:title "Insurance Information" .

<#family-history>
    a solid:TypeRegistration ;
    solid:forClass clinical:FamilyHistoryRecord ;
    solid:instance </clinical/family-history.ttl> ;
    dct:title "Family History" .

<#procedures>
    a solid:TypeRegistration ;
    solid:forClass clinical:Procedure ;
    solid:instance </clinical/procedures.ttl> ;
    dct:title "Procedures" .
```

### B.3 Standard Wellness Registrations

```turtle
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix health: <https://ns.cascadeprotocol.org/health/v1#> .
@prefix dct: <http://purl.org/dc/terms/> .

<#heart-rate>
    a solid:TypeRegistration ;
    solid:forClass health:HeartRateStatistics ;
    solid:instance </wellness/heart-rate.ttl> ;
    dct:title "Heart Rate Data" .

<#blood-pressure>
    a solid:TypeRegistration ;
    solid:forClass health:BPStatistics ;
    solid:instance </wellness/blood-pressure.ttl> ;
    dct:title "Blood Pressure Data" .

<#activity>
    a solid:TypeRegistration ;
    solid:forClass health:ActivitySnapshot ;
    solid:instance </wellness/activity.ttl> ;
    dct:title "Activity Data" .

<#sleep>
    a solid:TypeRegistration ;
    solid:forClass health:SleepStatistics ;
    solid:instance </wellness/sleep.ttl> ;
    dct:title "Sleep Data" .

<#hrv>
    a solid:TypeRegistration ;
    solid:forClass health:HRVStatistics ;
    solid:instance </wellness/hrv.ttl> ;
    dct:title "Heart Rate Variability" .

<#body-measurements>
    a solid:TypeRegistration ;
    solid:forClass health:BodyMeasurement ;
    solid:instance </wellness/body-measurements.ttl> ;
    dct:title "Body Measurements" .

<#supplements>
    a solid:TypeRegistration ;
    solid:forClass health:Supplement ;
    solid:instance </wellness/supplements.ttl> ;
    dct:title "Supplements" .
```

### B.4 Domain-Specific Registrations

```turtle
@prefix solid: <http://www.w3.org/ns/solid/terms#> .
@prefix checkup: <https://ns.cascadeprotocol.org/checkup/v1#> .
@prefix pots: <https://ns.cascadeprotocol.org/pots/v1#> .
@prefix dct: <http://purl.org/dc/terms/> .

# Checkup-specific registrations
<#daily-check-ins>
    a solid:TypeRegistration ;
    solid:forClass checkup:DailyCheckIn ;
    solid:instance </adherence/daily-check-ins.ttl> ;
    dct:title "Daily Check-ins" .

<#discussion-topics>
    a solid:TypeRegistration ;
    solid:forClass checkup:DiscussionTopic ;
    solid:instance </visit-prep/discussion-topics.ttl> ;
    dct:title "Discussion Topics" .

# POTS Check-specific registrations
<#pots-tests>
    a solid:TypeRegistration ;
    solid:forClass pots:POTSTest ;
    solid:instanceContainer </wellness/diagnostics/pots-checks/> ;
    dct:title "POTS Test Results" ;
    dct:description "NASA Lean Test results for POTS screening" .
```

---

## Appendix C: Manifest TTL Format

### C.1 Minimal Manifest

The smallest useful manifest records the export timestamp and schema version:

```turtle
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix prov: <http://www.w3.org/ns/prov#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix dct: <http://purl.org/dc/terms/> .

<#export>
    a cascade:PodExport ;
    prov:generatedAtTime "2026-02-19T10:00:00Z"^^xsd:dateTime ;
    cascade:exportFormat "solidPod" ;
    cascade:schemaVersion "1.3" ;
    dct:description "Cascade Protocol Pod Export" ;
    cascade:resourceCount 15 .
```

### C.2 Full Manifest with Provenance

A complete manifest includes the generating software agent and content summary:

```turtle
@prefix prov: <http://www.w3.org/ns/prov#> .
@prefix cascade: <https://ns.cascadeprotocol.org/core/v1#> .
@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
@prefix dct: <http://purl.org/dc/terms/> .
@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

<#manifest> a cascade:ExportManifest ;
    dct:title "Cascade Checkup Export" ;
    dct:created "2026-02-19T10:00:00Z"^^xsd:dateTime ;
    cascade:schemaVersion "1.3" ;
    cascade:exportFormat "solidPod" ;
    cascade:containerCount "15"^^xsd:integer ;
    cascade:totalRecords "142"^^xsd:integer ;
    cascade:includedCategories "12"^^xsd:integer ;
    prov:wasGeneratedBy [
        a prov:Activity ;
        prov:startedAtTime "2026-02-19T10:00:00Z"^^xsd:dateTime ;
        prov:wasAssociatedWith [
            a prov:SoftwareAgent ;
            rdfs:label "Cascade Checkup" ;
            cascade:exporterVersion "1.0"
        ]
    ] .
```

### C.3 Manifest Properties Reference

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `a` | `cascade:PodExport` or `cascade:ExportManifest` | REQUIRED | Resource type |
| `dct:created` or `prov:generatedAtTime` | `xsd:dateTime` | REQUIRED | Export timestamp |
| `cascade:schemaVersion` | Literal | REQUIRED | Protocol schema version |
| `cascade:exportFormat` | Literal | RECOMMENDED | `"solidPod"` or `"directory"` |
| `cascade:resourceCount` or `cascade:containerCount` | `xsd:integer` | RECOMMENDED | Number of data files |
| `cascade:totalRecords` | `xsd:integer` | OPTIONAL | Total record count |
| `cascade:includedCategories` | `xsd:integer` | OPTIONAL | Number of PHI categories |
| `dct:title` | Literal | OPTIONAL | Human-readable export name |
| `dct:description` | Literal | OPTIONAL | Longer description |
| `prov:wasGeneratedBy` | Blank node or URI | RECOMMENDED | Provenance activity chain |

---

## Appendix D: ACL File Templates

### D.1 Owner-Only ACL (Default)

Used for root, settings, and data container ACLs:

```turtle
@prefix acl: <http://www.w3.org/ns/auth/acl#> .
@prefix foaf: <http://xmlns.com/foaf/0.1/> .

# Owner has full control
<#owner>
    a acl:Authorization ;
    acl:agent <{OWNER_WEBID}> ;
    acl:accessTo <./> ;
    acl:default <./> ;
    acl:mode acl:Read, acl:Write, acl:Control .
```

Replace `{OWNER_WEBID}` with the Pod owner's WebID URI (e.g., `https://example.org/profile/card#me`).

### D.2 Profile ACL (Authenticated Read)

Used for the `profile/` directory:

```turtle
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<#owner>
    a acl:Authorization ;
    acl:agent <{OWNER_WEBID}> ;
    acl:accessTo <./card.ttl> ;
    acl:mode acl:Read, acl:Write, acl:Control .

<#public>
    a acl:Authorization ;
    acl:agentClass acl:AuthenticatedAgent ;
    acl:accessTo <./card.ttl> ;
    acl:mode acl:Read .
```

### D.3 Shared Container ACL (Grant Read to Specific Agent)

For sharing data with a specific agent (e.g., healthcare provider):

```turtle
@prefix acl: <http://www.w3.org/ns/auth/acl#> .

<#owner>
    a acl:Authorization ;
    acl:agent <{OWNER_WEBID}> ;
    acl:accessTo <./> ;
    acl:default <./> ;
    acl:mode acl:Read, acl:Write, acl:Control .

<#provider-read>
    a acl:Authorization ;
    acl:agent <{PROVIDER_WEBID}> ;
    acl:accessTo <./> ;
    acl:default <./> ;
    acl:mode acl:Read .
```

This pattern is not yet generated by the SDK but illustrates the intended sharing model for future Solid server integration.

---

*This specification is maintained as part of the Cascade Protocol documentation at [cascadeprotocol.org](https://cascadeprotocol.org). For implementation details, see the [CascadeSDK source](https://github.com/CascadeAgenticLabs/cascade-sdk-swift) `PodExporter.swift` and `PodNamespace.swift`.*
