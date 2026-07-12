# CivicRoute Build Manifest

This manifest is the single source of truth for the CivicRoute system implementation, compiled from the [CivicRoute_SRS.docx](file:///d:/Civic-Grievance-System/docs/CivicRoute_SRS.docx).

---

## 1. Functional Requirements

| ID | Functional Requirement | One-Line Restatement | Priority |
| --- | --- | --- | --- |
| **FR-1.1** [implemented] | System shall accept complaints via text, image, or audio, singly or combined. | Support multi-modal complaint submission using text, photos, and voice recordings. | High |
| **FR-1.2** [implemented] | System shall require at least one of text/image/audio per complaint. | Validate that each submitted complaint contains at least one text, image, or audio payload. | High |
| **FR-1.3** [implemented] | System shall accept location as GPS coordinates or free-text address. | Capture complaint location via automated GPS coordinates or manual text address input. | High |
| **FR-1.4** [implemented] | System shall return a complaint ID immediately without blocking on AI processing. | Instantly return a unique complaint ID to the citizen before commencing async backend AI analysis. | High |
| **FR-2.1** [implemented] | System shall transcribe voice complaints, detecting spoken language. | Transcribe audio complaints using Whisper and tag the detected spoken language (English/Tamil). | High |
| **FR-2.2** [implemented] | System shall classify each complaint into a department and subcategory with a confidence score. | Classify complaint text into a department/subcategory using MiniLM embeddings and FAISS search. | High |
| **FR-2.3** [implemented] | System shall route low-confidence classifications to an admin review queue instead of guessing. | Send complaints with classification confidence below a threshold to an admin triage queue. | High |
| **FR-2.4** [implemented] | System shall analyze submitted images for issue type and severity cues. | Classify images using CLIP zero-shot matching to extract civic issue type and estimate severity. | Medium |
| **FR-2.5** [implemented] | System shall flag disagreement between text-based and image-based classification for admin visibility. | Log a classification conflict for manual admin review if text and image classifications disagree. | Medium |
| **FR-3.1** [implemented] | System shall resolve a complaint's zone, ward, and responsible office from its location. | Run PostGIS spatial queries to map GPS coordinates to administrative zones, wards, and offices. | High |
| **FR-3.2** [implemented] | System shall geocode free-text addresses when coordinates are unavailable. | Convert manually typed addresses to coordinates using an open geocoding service. | High |
| **FR-3.3** [implemented] | System shall flag complaints whose location cannot be confidently resolved for manual assignment. | Route complaints with unresolved or ambiguous locations to an admin queue for manual assignment. | Medium |
| **FR-4.1** | System shall compute an explainable priority score and label for every complaint. | Calculate a deterministic priority score (0-100) and label based on weights, keywords, CV, and proximity. | High |
| **FR-4.2** | System shall detect and cluster duplicate/nearby complaints of the same issue. | Group concurrent complaints of the same category within ~100 meters and boost priority scores. | Medium |
| **FR-4.3** | System shall simultaneously notify the assigned officer and their supervisor upon routing. | Send real-time notifications to the assigned officer and cc the supervising authority upon routing. | High |
| **FR-4.4** | System shall set an SLA deadline based on department and priority at assignment time. | Establish a resolution deadline using department SLA hours, adjusted by priority multiplier. | High |
| **FR-5.1** | System shall enforce complaint status transitions via a defined state machine only. | Use an explicit finite state machine (FSM) to validate and enforce all complaint status transitions. | High |
| **FR-5.2** | System shall require evidence and a closing note before a complaint can be marked resolved. | Restrict status changes to resolved unless a closing note and evidence photo are uploaded. | High |
| **FR-5.3** | System shall require supervisor approval before a resolved complaint is closed. | Require a supervising authority to approve resolved complaints before they can transition to closed. | High |
| **FR-5.4** | System shall auto-escalate complaints that breach their SLA deadline. | Automatically transition complaints to escalated and notify supervisors if the SLA deadline is missed. | High |
| **FR-5.5** | System shall maintain a complete, immutable audit trail of every status change and actor. | Write a persistent, unchangeable event log entry for every status transition and administrative action. | High |
| **FR-6.1** | System shall push real-time notifications to citizens, officers, and supervisors. | Propagate instant status update notifications to relevant roles via Supabase Realtime subscriptions. | High |
| **FR-6.2** | Citizens shall be able to view the full timeline of their complaint at any time. | Expose the complete, transparent historical timeline of a complaint's lifecycle to the citizen. | High |
| **FR-6.3** | System shall display the priority-score breakdown to officers/supervisors for transparency. | Display the explicit list of contributing rules and weights behind the calculated priority score. | Medium |

---

## 2. Section 4 Modules & Internal Steps

| Module | Module Name | Condensed Internal Step List |
| --- | --- | --- |
| **4.1** [implemented] | Speech-to-Text Module | <ul><li>Validate audio format, duration, and size.</li><li>Run local Whisper model (small/base multilingual) to transcribe the speech.</li><li>Detect and tag the spoken language (English/Tamil) without automatic translation.</li><li>Persist the transcript and language tag to the complaint database record.</li><li>Log a `audio_transcribed` event with model-confidence for audit.</li></ul> |
| **4.2** [implemented] | NLP Complaint Understanding & Department Classification | <ul><li>Normalize input text (lowercase, strip noise, translate Tamil-English civic terms).</li><li>Generate text sentence embedding using a lightweight MiniLM transformer.</li><li>Query a FAISS index of reference phrases for department similarity (cosine-similarity).</li><li>If match score $\ge$ threshold (e.g. 0.55), select department and query subcategories.</li><li>If match score < threshold, tag department as `needs_review` and route to admin triage.</li><li>Persist resolved department ID, subcategory, and similarity confidence score.</li></ul> |
| **4.3** [implemented] | Computer Vision Module | <ul><li>Validate image and filter out/flag irrelevant or low-quality photos.</li><li>Run zero-shot CLIP classification against fixed labels (pothole, garbage, etc.).</li><li>Map top label + confidence score to a severity hint (minor/moderate/severe).</li><li>Cross-check label against NLP department; log a conflict event if they disagree.</li><li>Persist image label, confidence, severity hint, and conflict flag.</li></ul> |
| **4.4** [implemented] | GIS / Location Intelligence Module | <ul><li>Retrieve GPS coordinates if provided; otherwise, geocode typed address and cache.</li><li>Execute PostGIS `ST_Contains` query against ward/zone polygons to resolve ward.</li><li>If outside boundaries, find nearest ward centroid (max radius) or flag `jurisdiction_uncertain`.</li><li>Cross-reference ward and department; escalate to parent zone office if no ward office.</li><li>Persist resolved jurisdiction ID, resolution method, and uncertainty status.</li></ul> |
| **4.5** | Priority / Severity Scoring Engine | <ul><li>Assign base priority points based on resolved department category configuration.</li><li>Add priority points if text contains critical keywords (danger, accident, elderly, etc.).</li><li>Add priority points based on CV severity hint if an image is attached.</li><li>Run PostGIS `ST_DWithin` to find nearby department complaints (< 100m, < 30 days) and apply cluster boost.</li><li>Apply time-decay priority boost if complaint exceeds SLA deadline.</li><li>Calculate final score (0-100), map to label, and save score breakdown dictionary.</li></ul> |
| **4.6** | Routing Engine | <ul><li>Look up the field officer matching the resolved jurisdiction ID and department ID.</li><li>Look up the supervising authority for the identified field officer.</li><li>Compute SLA deadline (adjusted shorter if priority is Critical).</li><li>Delegate to FSM to transition complaint status to `assigned`.</li><li>Write real-time notifications for the officer, supervisor, and citizen.</li></ul> |
| **4.7** | Workflow Automation Engine (Finite State Machine) | <ul><li>Maintain explicit FSM transition rule table (source state, action, role, target state).</li><li>Validate all status transitions against FSM rules and requester permissions.</li><li>Enforce closing photo evidence and resolution notes before allowing resolution.</li><li>Run scheduled jobs to check for SLA breaches and transition active complaints to `escalated`.</li><li>Append an immutable record to the `complaint_events` audit log.</li></ul> |
| **4.8** | Real-Time Notification Service | <ul><li>Insert notification records into DB on assignment, status change, escalation, or approval.</li><li>Expose changes to clients via Supabase Realtime Postgres change-stream.</li><li>Update notification read status via FastAPI API endpoint.</li></ul> |
| **4.9** | Narrative Summary Generator | <ul><li>Gather finalized structured attributes (department, priority, ward, status, timeline).</li><li>Format structured attributes into a prompt and send to local LLM (Ollama llama3).</li><li>Validate that LLM output does not introduce hallucinated facts, and save or fallback.</li></ul> |

---

## 3. Section 7 Core Entities & Key Attributes

| Entity | Key Attributes | Status |
| --- | --- | --- |
| **departments** | `id`, `name`, `category`, `sla_hours` | Implemented |
| **jurisdictions** | `id`, `zone`, `ward`, `area_name`, `boundary` (PostGIS polygon), `department_id`, `office_name`, `officer_contact` | Implemented |
| **users** | `id`, `name`, `role` (citizen/officer/supervisor/admin), `phone`, `email`, `jurisdiction_id` | Implemented |
| **complaints** | `id`, `citizen_id`, `raw_text`, `image_url`, `audio_url`, `transcribed_text`, `category`, `subcategory`, `department_id`, `jurisdiction_id`, `priority_score`, `priority_label`, `status`, `location` (PostGIS point), `address_text`, `cluster_id`, `sla_deadline`, `created_at` | Implemented |
| **complaint_events** | `id`, `complaint_id`, `actor_id`, `action`, `note`, `created_at` (immutable audit log) | Implemented |
| **notifications** | `id`, `user_id`, `complaint_id`, `message`, `channel`, `read_at`, `created_at` | Implemented |

---

## 4. Open Questions

The following implementation ambiguities have been identified in the SRS:

1. **FSM Transition Conflict**: 
   The FSM diagram (`fsm.png`) shows a red transition line pointing from `ESCALATED` to `CLOSED` labeled *"supervisor re-assigns"*. However, standard business logic suggests that re-assignment should return a complaint to `ASSIGNED` or `IN_PROGRESS`. Does a supervisor re-assignment move the complaint back to a resolution queue, or does a supervisor have a distinct "close escalated" action that directly closes the complaint?
2. **Tamil-English Lookup Table**:
   Where is the Tamil-English civic-term lookup table (e.g. `'thanni'` $\rightarrow$ water) stored, and what are its initial contents? Is it hardcoded in the Python backend, stored as a config file, or managed dynamically in the database via the admin dashboard?
3. **Ollama LLM Integration**:
   For the Narrative Summary Generator (4.9), how is the Ollama service hosted and reached by the FastAPI backend? Is it running in a shared Docker network, or is there an external API URL/key to use? What is the standard fallback prompt/behavior if the LLM service is offline or times out?
4. **NLP & CV Similarity Thresholds**:
   What are the exact confidence threshold values for department classification (NLP) and zero-shot labeling (CV) to trigger low-confidence review routes or classification conflicts?
5. **Priority Scoring Constants**:
   What are the specific numerical weights and points associated with:
   - Department categories (base weight)
   - Text keywords (keyword weights)
   - Proximity duplicates (clustering weight)
   - CV severity hints (minor/moderate/severe weights)
   - Time-decay boost rates
6. **JWT Signature Verification**:
   Should the FastAPI backend verify the Supabase JWT locally using the Supabase JWT secret key, or does it query Supabase's user profile endpoint dynamically on each API call?
