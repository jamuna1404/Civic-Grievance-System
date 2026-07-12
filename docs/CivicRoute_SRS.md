
SOFTWARE REQUIREMENTS SPECIFICATION
AI-Powered Intelligent Government Complaint
Routing and Resolution System  —  "CivicRoute"
Document Version 1.0
Prepared as an academic project specification, conforming to IEEE 830 SRS structure

# Document Control
| Version | Date | Description | Author |
| --- | --- | --- | --- |
| 1.0 | July 2026 | Initial SRS draft covering full system scope | Project Author |


Table of Contents

# 1. Introduction
## 1.1 Purpose
This Software Requirements Specification (SRS) defines the functional and non-functional requirements, system architecture, and internal processing design for CivicRoute — an AI-assisted platform that automatically classifies, prioritizes, geo-locates, and routes citizen-submitted civic complaints to the correct government department and jurisdictional office, and tracks each complaint through a supervised resolution workflow.
A core design principle of this document is that intelligence in the system is implemented as explicit, auditable, deterministic processing modules — not as a single prompt handed to a large language model. Each module listed in Section 4 has its own internal pipeline of steps, each of which can be tested, logged, and explained independently. A generative language model is used in exactly one place (Section 4.9) to produce a human-readable narrative summary after all classification and scoring decisions have already been made by rule-based and embedding-based logic — it never decides department, priority, or routing.
## 1.2 Scope
The system covers: multi-modal complaint intake (text, image, voice); automated department classification via NLP; automated issue/severity cues via computer vision; GIS-based jurisdiction resolution (zone/ward/office); a deterministic priority scoring engine; a routing engine that simultaneously notifies the responsible officer and supervising authority; a finite-state workflow engine tracking a complaint from registration to closure, including SLA-based escalation; real-time notifications; and role-based dashboards for citizens, officers, supervisors, and administrators.
Out of scope for the initial version: payment/penalty processing, integration with legacy government ERP systems, legal/RTI request handling, and multi-lingual support beyond English and Tamil.
## 1.3 Intended Audience
Project guide / evaluators reviewing technical depth and feasibility
The developer (solo, full-stack + ML background) implementing the system
Future collaborators or open-source contributors extending the platform
## 1.4 Definitions, Acronyms, Abbreviations
| Term | Meaning |
| --- | --- |
| GIS | Geographic Information System — spatial data mapping administrative boundaries |
| NLP | Natural Language Processing |
| CV | Computer Vision |
| SLA | Service Level Agreement — maximum allowed resolution time per department |
| FSM | Finite State Machine — governs valid complaint status transitions |
| Jurisdiction | A ward/zone administrative unit mapped to a responsible office |
| Confidence Score | Numeric certainty (0-1) output by a classifier for its own prediction |
| Cluster | A group of independent complaints identified as referring to the same underlying issue |

## 1.5 References
IEEE Std 830-1998 — Recommended Practice for Software Requirements Specifications
PostGIS Documentation — spatial query functions (ST_Contains, ST_DWithin)
sentence-transformers / FAISS documentation — semantic similarity search
OpenAI Whisper / faster-whisper documentation — speech-to-text

# 2. Overall Description
## 2.1 Product Perspective
CivicRoute is a new, standalone system, not a modification of an existing product. It is designed so that individual intelligence modules (NLP classifier, CV analyzer, GIS resolver, priority engine) are decoupled services that can each be replaced, retrained, or upgraded independently without altering the workflow engine or citizen-facing contract. This decoupling is deliberate: government systems change classification taxonomies and jurisdiction boundaries far more often than they change their approval workflow.
## 2.2 Problem Statement (from Abstract)
Citizens do not reliably know which department is responsible for an issue, which office has jurisdiction over their location, or what format a complaint must follow. Existing portals require the citizen to manually pick a department and office from a list, which causes misrouted complaints, silent drops, and long resolution delays with no visible accountability chain.
## 2.3 Product Functions (Summary)
Accept complaints via text, photo, or voice, in English or Tamil (code-switched)
Automatically determine complaint category, department, and subcategory
Automatically determine administrative zone, ward, and responsible office from location
Automatically compute an explainable priority score and detect duplicate/clustered complaints
Automatically assign the complaint to the correct officer and cc the supervising authority
Track the complaint through a controlled workflow with SLA-based auto-escalation
Deliver real-time status notifications to all stakeholders
Provide dashboards: citizen tracking, officer action queue, supervisor approval/escalation view, admin GIS analytics map
## 2.4 User Classes and Characteristics
| User Class | Description | Technical Proficiency |
| --- | --- | --- |
| Citizen | General public submitting/tracking complaints | Low — mobile-first, minimal text entry expected |
| Field Officer | Government staff resolving assigned complaints | Low-Medium — simple task queue UI |
| Supervisor | Approves resolutions, monitors SLA/escalations | Medium |
| Admin | Manages departments, jurisdictions, taxonomy | Medium-High |

## 2.5 Operating Environment
Backend: FastAPI (Python), containerized via Docker, hosted on any Linux-compatible container host
Database & Backend-as-a-Service: Supabase — managed PostgreSQL with the PostGIS extension enabled, plus Supabase Auth, Supabase Storage, and Supabase Realtime used directly rather than hand-rolled equivalents
Client: Flutter, single codebase compiled to Android and iOS for citizens, and to Flutter Web for officer, supervisor, and admin dashboards — this removes the need for a separate web frontend framework and keeps UI logic in one language/codebase
ML inference: CPU-feasible models chosen deliberately (MiniLM embeddings, Whisper-small/base, CLIP) so the system does not require GPU hosting for a college/portfolio deployment; inference runs inside the FastAPI backend, never on-device in Flutter
## 2.6 Design and Implementation Constraints
No paid/licensed APIs assumed available by default (geocoding, maps, SMS) — the design uses free/open alternatives (OpenStreetMap/Nominatim, flutter_map with OSM tiles) with clearly marked swap points for production-grade paid services
Solo-developer build — architecture favors modular monolith (FastAPI) over microservices, and Supabase over self-hosted auth/storage/realtime, to minimize infrastructure the developer must operate directly
Supabase's built-in Auth, Storage, and Realtime are treated as the authoritative implementation for those concerns; FastAPI should not duplicate them (e.g. no separate JWT auth system, no separate WebSocket server, no local disk file storage in any deployed environment)
Must run demonstrably via docker-compose (FastAPI + a local Postgres/PostGIS for offline dev) with a documented path to point the same code at a hosted Supabase project for the live demo
## 2.7 Assumptions and Dependencies
Jurisdiction boundary data (ward/zone polygons) is available or can be reasonably approximated for the demo city/area
Citizens have a smartphone with camera, microphone, and GPS for full-feature use; text-only submission remains supported as a fallback
Officers and supervisors are pre-provisioned in the system by an admin; open self-registration is not intended for these roles

# 3. System Architecture
The architecture is organized into eight layers, each with a single clear responsibility. Data flows strictly downward through the intelligence layers before reaching the routing and workflow layers — no layer is allowed to skip ahead and "decide" something outside its responsibility (e.g. the CV module never assigns a department on its own; it only contributes a signal that the NLP+priority layers consume).

Figure 1: CivicRoute layered system architecture
## 3.1 Layer Responsibilities
| Layer | Responsibility | Key Technologies |
| --- | --- | --- |
| Citizen Interface | Multi-modal submission, status view, notifications | Flutter (Android/iOS), device camera/mic/GPS APIs |
| Ingestion & Pre-processing | Validate input, store files, dispatch async processing | FastAPI, Supabase Storage, background task queue |
| AI Understanding (NLP/CV/ASR) | Independently analyze text, image, and voice | spaCy, sentence-transformers, FAISS, Whisper, CLIP |
| Decision Support (Priority + GIS) | Deterministic scoring and jurisdiction resolution | Rule engine, Supabase Postgres + PostGIS, geocoding |
| Routing Engine | Combine outputs into a final officer/supervisor assignment | Custom business logic service (FastAPI) |
| Workflow Automation | Enforce valid status transitions, SLA timers | Explicit finite state machine, scheduler |
| Dashboards & Notifications | Role-based UI, real-time updates | Flutter Web, Supabase Realtime |
| Persistence & Audit | Durable storage and full action history | Supabase Postgres + PostGIS, event log table |

## 3.2 Complaint Lifecycle
Every complaint moves through a controlled set of states. Transitions are only permitted by the specific actor and precondition shown below; any other transition is rejected by the API layer, not merely discouraged by the UI.

Figure 2: Complaint lifecycle finite state machine

# 4. Detailed Module Design (Internal Workflows)
This section is the direct answer to the requirement that no module reduce to "send the complaint to an LLM and use whatever comes back." Every module below is a pipeline of named, independently testable steps. Confidence thresholds create explicit fallback-to-human-review paths rather than forcing a guess.
## 4.1 Speech-to-Text Module
Converts voice complaints into text so the NLP module can process them uniformly with typed complaints.
### Internal Processing Steps (deterministic pipeline)
Step 1: Receive audio file; validate format/duration/size.
Step 2: Run local Whisper (small/base multilingual model) for transcription.
Step 3: Capture the detected spoken language (English or Tamil) alongside the transcript — no auto-translation, to avoid losing meaning through a second lossy step.
Step 4: Store transcript and language tag on the complaint record.
Step 5: Log a complaint_event 'audio_transcribed' with a model-confidence indicator for audit.
Why this is not "just an LLM call": Transcription is a fixed, single-purpose ASR model call with deterministic output for a given audio input — no generative reasoning or decision-making occurs here; it only produces text for the next stage.
## 4.2 NLP Complaint Understanding & Department Classification
Determines which government department a complaint belongs to, and its subcategory, from whichever text is available.
### Internal Processing Steps (deterministic pipeline)
Step 1: Normalize text: lowercase, strip noise, apply a Tamil-English civic-term lookup table (e.g. 'thanni' → water) so code-switched input is not lost to a generic tokenizer.
Step 2: Generate a sentence embedding of the normalized text using a lightweight transformer (MiniLM).
Step 3: Compare the embedding against a maintained FAISS index of reference phrases per department (built once from curated example complaints, not generated at runtime).
Step 4: Return the nearest department match with a cosine-similarity confidence score.
Step 5: If confidence ≥ threshold (e.g. 0.55): run a second, narrower FAISS match restricted to that department's subcategories.
Step 6: If confidence < threshold: mark department as 'needs_review' and route to an admin triage queue instead of forcing an assignment.
Step 7: Persist department_id, subcategory, and the raw confidence score (for later audit/tuning).
Why this is not "just an LLM call": Classification is nearest-neighbour search over a fixed, human-curated reference set with a numeric, inspectable confidence score and an explicit low-confidence fallback — this is standard applied ML, not a prompt asking a generative model to 'pick a department.'
## 4.3 Computer Vision Module
Extracts issue-type and severity cues from a submitted photo to corroborate or supplement the text classification.
### Internal Processing Steps (deterministic pipeline)
Step 1: Validate image; reject/flag unclear or irrelevant photos using a defined 'irrelevant/unclear' label in the zero-shot label set.
Step 2: Run a zero-shot image classifier (CLIP) against a fixed civic-issue label set (pothole, garbage pile, broken streetlight, pipe leak, etc.).
Step 3: Map the top label + its confidence to a severity_hint tier (minor/moderate/severe) via a documented, tunable lookup table — not a free-form judgment.
Step 4: Cross-check the CV label against the NLP department result; if they disagree, log a 'classification_conflict' event for admin visibility rather than silently picking one.
Step 5: Persist label, confidence, severity_hint, and conflict flag (if any) for audit.
Why this is not "just an LLM call": The CV step is a closed-set zero-shot classification against pre-defined labels with a fixed confidence→severity mapping table, and disagreements are surfaced rather than resolved by an opaque model call.
## 4.4 GIS / Location Intelligence Module
Resolves a raw location (GPS point or typed address) into an administrative zone, ward, and the specific office responsible for that department in that ward.
### Internal Processing Steps (deterministic pipeline)
Step 1: If GPS coordinates were submitted, use them directly; otherwise geocode the typed address via an open geocoder, with results cached by address string.
Step 2: Run a PostGIS ST_Contains spatial query against stored jurisdiction polygons to find the containing ward/zone.
Step 3: If no polygon contains the point (edge case), fall back to the nearest jurisdiction centroid within a max radius and flag 'jurisdiction_uncertain' for manual admin assignment — never guess silently.
Step 4: Cross-reference the resolved ward with the department from Module 2: if that department has no local ward-level office, escalate the lookup to the parent zone office.
Step 5: Persist jurisdiction_id, resolution method used, and any uncertainty flag.
Why this is not "just an LLM call": Location resolution is a geometric containment query against authoritative polygon data, with an explicit, logged fallback path — a fundamentally different (and more reliable) operation than asking a model to 'guess the ward from an address.'
## 4.5 Priority / Severity Scoring Engine
Produces a numeric, explainable priority score and label used to order officer queues and drive SLA timers.
### Internal Processing Steps (deterministic pipeline)
Step 1: Start from a department base-weight (e.g. contamination/health-risk categories weighted above cosmetic issues) from a configuration table.
Step 2: Add points for severity keywords present in the text (danger, accident, children, elderly, urgent) from a maintained keyword list.
Step 3: Add the CV module's severity_hint contribution, if an image was provided.
Step 4: Query for other open complaints of the same department within ~100m in the last 30 days (PostGIS ST_DWithin); if 3 or more exist, boost priority and link all of them via a shared cluster_id — this flags widespread real issues rather than one-off noise.
Step 5: Apply an SLA time-decay boost if the complaint has been open longer than its department's SLA, and mark it 'at_risk'.
Step 6: Sum all factors into a 0–100 score and map to Low/Medium/High/Critical, storing a full breakdown dict of exactly which factors fired and by how much.
Why this is not "just an LLM call": Every point in the final score is traceable to a specific rule (keyword hit, cluster size, time decay, base weight) stored alongside the score itself — this is a transparent rule-based scoring engine precisely so priority decisions can be explained to a citizen or auditor, which a single LLM score could not reliably guarantee.
## 4.6 Routing Engine
Converts the outputs of Modules 2-5 into a concrete assignment: which officer, which supervisor, and by when.
### Internal Processing Steps (deterministic pipeline)
Step 1: Look up the officer whose jurisdiction_id and department match the resolved values from Modules 2 and 4.
Step 2: Look up that officer's supervising authority.
Step 3: Compute sla_deadline = now + department SLA hours, shortened for Critical-priority complaints per a configured multiplier.
Step 4: Transition complaint status to 'assigned' via the workflow engine (Module 7) — the routing engine itself never sets status directly; it delegates to the FSM to keep transition rules centralized.
Step 5: Create notification records for officer, supervisor, and citizen simultaneously, satisfying the abstract's accountability requirement that both actor and supervisor are informed at once.
## 4.7 Workflow Automation Engine (Finite State Machine)
Owns all complaint status transitions so that the process from registration to closure is enforced consistently regardless of which module or actor triggers a change.
### Internal Processing Steps (deterministic pipeline)
Step 1: Define allowed transitions explicitly as a table (from_state, action, actor_role, to_state) rather than scattered conditional logic.
Step 2: Validate every transition request against this table and the actor's own jurisdiction/role before applying it.
Step 3: mark_resolved requires an evidence image and closing note as preconditions, not optional extras.
Step 4: A scheduled job periodically checks for SLA breaches on assigned/in_progress complaints and auto-transitions them to 'escalated', notifying the supervisor.
Step 5: Every transition writes an immutable complaint_event row, forming the audit trail citizens and supervisors both see.
## 4.8 Real-Time Notification Service
Delivers status changes to citizens, officers, and supervisors without manual refreshing.
### Internal Processing Steps (deterministic pipeline)
Step 1: On any notification-worthy event (assignment, status change, escalation, approval/rejection), write a notification row scoped to the relevant user.
Step 2: Rely on Supabase Realtime's built-in Postgres change-stream subscription on the notifications table — the Flutter client subscribes directly to its own row filter (user_id = current user) rather than the backend maintaining a separate push/WebSocket layer.
Step 3: Client marks notifications read via an explicit acknowledgement call (FastAPI endpoint, which updates the row that Realtime then propagates as an UPDATE event), keeping an accurate unread count.
## 4.9 Narrative Summary Generator (the one LLM touchpoint)
Produces a short, readable natural-language summary of a complaint's classification and status for display to citizens and in officer/supervisor views — purely descriptive, never decisional.
### Internal Processing Steps (deterministic pipeline)
Step 1: Gather already-finalized structured facts: department, subcategory, priority breakdown, jurisdiction, current status, and timeline.
Step 2: Pass these structured facts (not the raw complaint) to a local LLM (e.g. Ollama llama3) with a constrained prompt to phrase them as a short paragraph.
Step 3: Discard the LLM output if it introduces any field value not present in the structured input (a simple guardrail check), regenerating or falling back to a template sentence if so.
Why this is not "just an LLM call": This is the only step in the entire pipeline that touches a generative model, and it is invoked strictly after every classification, priority, and routing decision has already been made deterministically — the LLM only writes the sentence, it never picks the department, ward, priority, or officer.

# 5. Functional Requirements
Each requirement below is uniquely numbered for traceability into test cases and Claude Code build prompts.
## 5.1 Complaint Intake
| ID | Requirement | Priority |
| --- | --- | --- |
| FR-1.1 | System shall accept complaints via text, image, or audio, singly or combined. | High |
| FR-1.2 | System shall require at least one of text/image/audio per complaint. | High |
| FR-1.3 | System shall accept location as GPS coordinates or free-text address. | High |
| FR-1.4 | System shall return a complaint ID immediately without blocking on AI processing. | High |

## 5.2 AI Understanding
| ID | Requirement | Priority |
| --- | --- | --- |
| FR-2.1 | System shall transcribe voice complaints, detecting spoken language. | High |
| FR-2.2 | System shall classify each complaint into a department and subcategory with a confidence score. | High |
| FR-2.3 | System shall route low-confidence classifications to an admin review queue instead of guessing. | High |
| FR-2.4 | System shall analyze submitted images for issue type and severity cues. | Medium |
| FR-2.5 | System shall flag disagreement between text-based and image-based classification for admin visibility. | Medium |

## 5.3 Location Intelligence
| ID | Requirement | Priority |
| --- | --- | --- |
| FR-3.1 | System shall resolve a complaint's zone, ward, and responsible office from its location. | High |
| FR-3.2 | System shall geocode free-text addresses when coordinates are unavailable. | High |
| FR-3.3 | System shall flag complaints whose location cannot be confidently resolved for manual assignment. | Medium |

## 5.4 Priority & Routing
| ID | Requirement | Priority |
| --- | --- | --- |
| FR-4.1 | System shall compute an explainable priority score and label for every complaint. | High |
| FR-4.2 | System shall detect and cluster duplicate/nearby complaints of the same issue. | Medium |
| FR-4.3 | System shall simultaneously notify the assigned officer and their supervisor upon routing. | High |
| FR-4.4 | System shall set an SLA deadline based on department and priority at assignment time. | High |

## 5.5 Workflow & Accountability
| ID | Requirement | Priority |
| --- | --- | --- |
| FR-5.1 | System shall enforce complaint status transitions via a defined state machine only. | High |
| FR-5.2 | System shall require evidence and a closing note before a complaint can be marked resolved. | High |
| FR-5.3 | System shall require supervisor approval before a resolved complaint is closed. | High |
| FR-5.4 | System shall auto-escalate complaints that breach their SLA deadline. | High |
| FR-5.5 | System shall maintain a complete, immutable audit trail of every status change and actor. | High |

## 5.6 Notification & Transparency
| ID | Requirement | Priority |
| --- | --- | --- |
| FR-6.1 | System shall push real-time notifications to citizens, officers, and supervisors. | High |
| FR-6.2 | Citizens shall be able to view the full timeline of their complaint at any time. | High |
| FR-6.3 | System shall display the priority-score breakdown to officers/supervisors for transparency. | Medium |


# 6. Non-Functional Requirements
| Category | Requirement |
| --- | --- |
| Performance | Complaint submission API shall respond within 1s; full AI pipeline (classification→routing) shall complete within 15s for 95% of complaints on CPU-only inference. |
| Scalability | Architecture shall support horizontal scaling of the background-processing workers independently of the API layer (modular monolith designed to split into services later). |
| Availability | Core submission and status-tracking APIs shall target 99% uptime during a demo/pilot deployment window. |
| Security | Role-based access control shall restrict officer/supervisor actions to their own jurisdiction, enforced both in FastAPI and via Supabase Row-Level Security policies; all file uploads shall be validated for type/size before storage in Supabase Storage buckets. |
| Usability | Citizen-facing UI shall be mobile-first and usable with minimal typing (voice/photo-first submission). |
| Auditability | Every automated decision (classification, priority, routing) shall be stored with its contributing factors, not just the final outcome. |
| Maintainability | Each intelligence module (NLP, CV, GIS, Priority) shall be independently swappable/retrainable without changes to the workflow engine's contract. |
| Localization | System shall support English and Tamil-English code-switched text input in v1; architecture shall allow adding further languages via the lookup-table/embedding approach without redesign. |


# 7. Data Requirements (Core Entities)
| Entity | Key Attributes |
| --- | --- |
| departments | id, name, category, sla_hours |
| jurisdictions | id, zone, ward, area_name, boundary (PostGIS polygon), department_id, office_name, officer_contact |
| users | id, name, role (citizen/officer/supervisor/admin), phone, email, jurisdiction_id |
| complaints | id, citizen_id, raw_text, image_url, audio_url, transcribed_text, category, subcategory, department_id, jurisdiction_id, priority_score, priority_label, status, location (point), address_text, cluster_id, sla_deadline, created_at |
| complaint_events | id, complaint_id, actor_id, action, note, created_at (immutable audit log) |
| notifications | id, user_id, complaint_id, message, channel, read_at, created_at |


# 8. External Interface Requirements
## 8.1 Key API Endpoints
| Endpoint | Purpose |
| --- | --- |
| POST /api/complaints | Submit a new complaint (text/image/audio + location) |
| GET /api/complaints/{id} | Retrieve complaint detail |
| GET /api/complaints/{id}/timeline | Retrieve full audit trail / notifications for a complaint |
| POST /api/complaints/{id}/actions | Officer actions: start_work, mark_resolved, request_more_info, escalate |
| POST /api/complaints/{id}/approve | Supervisor approval or rejection of a resolved complaint |
| GET /api/notifications | List a user's notifications (client also subscribes directly to the Supabase Realtime channel on this table for live push) |

## 8.2 User Interfaces
All roles are served by a single Flutter codebase, compiled to Android/iOS for citizens and to Flutter Web for internal staff — this keeps UI logic, widgets, and API-client code shared across a single language rather than maintaining a separate web framework alongside a mobile app.
Citizen (Flutter mobile): submission form, complaint list, complaint detail/timeline
Officer (Flutter Web): prioritized action queue, action detail view
Supervisor (Flutter Web): cross-jurisdiction overview, approval queue, escalation panel, analytics strip
Admin (Flutter Web): GIS map dashboard with density/priority overlays and filters
## 8.3 Authentication
All roles authenticate via Supabase Auth (email/phone OTP for citizens; email/password for officers, supervisors, and admins provisioned by an admin).
FastAPI validates the Supabase-issued JWT on every request rather than maintaining its own session/auth store.
Row-Level Security (RLS) policies in Supabase Postgres provide a second enforcement layer beneath the FastAPI role checks — e.g. an officer's queries are restricted at the database level to their own jurisdiction, not solely by application logic.

# 9. Feasibility Study
## 9.1 Technical Feasibility
All chosen components (sentence-transformers, FAISS, Whisper small/base, CLIP zero-shot, PostGIS, FastAPI, Flutter, Supabase) are open-source or offer a generous free tier, run acceptably on CPU for a demo-scale dataset, and are already within the developer's existing skill set (spaCy/sentence-transformers/FAISS reused directly from a prior project; Supabase already used as the auth/DB layer on the Resume to Readiness project). Supabase specifically removes the need to hand-build auth, file storage, and a real-time push layer, which is a meaningful reduction in solo-developer scope without reducing functional completeness. No component requires a paid API key to demonstrate end-to-end functionality, though production deployment would benefit from a paid geocoder for India-wide address accuracy.
## 9.2 Operational Feasibility
The workflow mirrors how grievance redressal already works administratively (officer executes, supervisor approves), so adoption requires no conceptual retraining of staff — only a new interface for an existing approval pattern. A single Flutter codebase serving both the citizen mobile app and the staff web dashboards also reduces the number of things that can drift out of sync between platforms. The explicit priority breakdown and audit trail directly address the transparency and accountability goals stated in the abstract.
## 9.3 Economic Feasibility
Infrastructure cost for a pilot is limited to Supabase's free/low-cost tier (Postgres+PostGIS, Auth, Storage, Realtime bundled) and compute for CPU inference; all core ML models are free and self-hosted within the FastAPI backend. The main future cost driver would be a production-grade geocoding/SMS provider and a paid Supabase tier at scale, both of which are optional scaling decisions rather than architectural requirements.
## 9.4 Schedule Feasibility
The system is scoped into 15 incremental build stages (scaffolding → intelligence modules → workflow → dashboards → hardening), each independently testable, making it realistic for a solo developer to complete within a typical single-semester project timeline while maintaining a working, demoable system at every stage rather than only at the very end.
## 9.5 Risk Register
| Risk | Mitigation |
| --- | --- |
| Low classification confidence on ambiguous complaints | Explicit 'needs_review' fallback to admin triage instead of forced misassignment |
| Geocoding inaccuracy for informal addresses | Cache + fallback-to-nearest-jurisdiction path, clearly flagged as uncertain |
| CPU inference latency at scale | Async background processing; models chosen specifically for CPU feasibility |
| Jurisdiction boundary data unavailable for demo region | Use approximated/synthetic ward polygons for demonstration, documented as such |


# 10. Appendix — Traceability to Abstract
| Abstract Statement | Addressed By |
| --- | --- |
| "Automatically understands citizen complaints submitted through images, text, or voice" | Modules 4.1–4.3 (ASR, NLP, CV) |
| "Extracts the complaint location... identifies the responsible government department" | Modules 4.2, 4.4 |
| "Estimates the complaint priority based on severity" | Module 4.5 |
| "Routes it to the appropriate jurisdictional office" | Modules 4.4, 4.6 |
| "Determines administrative area, zone, ward, and responsible local office" | Module 4.4 (GIS) |
| "Forwards the complaint simultaneously to the concerned officer and supervising authority" | Module 4.6 (Routing Engine) |
| "Dynamic workflow tracks complaint progress... officers update actions... supervisors approve" | Module 4.7 (FSM) |
| "Citizens receive real-time notifications... monitor status transparently" | Module 4.8, FR-6.1–6.3 |
