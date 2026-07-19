# CivicRoute — Implementation Build Guide (SRS-Aligned, Flutter + FastAPI + Supabase)
### Sequential Claude Code Prompts

**How to use this:** Paste these into Claude Code **one at a time, in the same repo**, in order. Let each stage finish, run, and pass its acceptance check before moving to the next. Every prompt tells the agent to open `CivicRoute_SRS.docx` for the exact clause it's implementing, keeping the build traceable to FR-x.x and module 4.x from the SRS.

Put `CivicRoute_SRS.docx` in the repo root (e.g. `/docs/CivicRoute_SRS.docx`) before starting Prompt 1.

Stack: **FastAPI** (backend/ML), **Supabase** (Postgres + PostGIS, Auth, Storage, Realtime), **Flutter** (single codebase → Android/iOS for citizens, Flutter Web for officer/supervisor/admin).

---

## Prompt 0 — Read the SRS, Produce a Build Manifest

```
Read /docs/CivicRoute_SRS.docx in full (convert to text/markdown first if needed — pandoc works well).

Produce /docs/BUILD_MANIFEST.md listing, in a table:
- every Functional Requirement ID (FR-1.1 through FR-6.3) with a one-line restatement
- every module from Section 4 (4.1 through 4.9) with its internal step list condensed to bullet points
- the core entities from Section 7 with their key attributes

This manifest is the single source of truth you will check off against in later prompts — do not invent requirements not present in the SRS, and do not silently drop any FR-x.x. If anything is ambiguous, list it under a final "Open Questions" section instead of guessing.

Do not write any application code in this prompt — comprehension/planning only.
Acceptance: BUILD_MANIFEST.md exists and every FR-x.x and module 4.x from the SRS appears in it exactly once.
```

---

## Prompt 1 — Project Scaffolding (FastAPI + Supabase + Flutter)

```
Referencing /docs/BUILD_MANIFEST.md and SRS Section 2.5 (Operating Environment), set up the project skeleton for the stack: FastAPI backend, Supabase as the data/auth/storage/realtime layer, Flutter as the single client for both mobile (citizen) and web (officer/supervisor/admin).

/backend
  /app/api            (FastAPI routers)
  /app/core           (config, Supabase client init, security/JWT validation)
  /app/models         (SQLAlchemy models)
  /app/schemas        (Pydantic schemas)
  /app/services       (nlp, cv, gis, priority, routing, workflow, notifications, narrative)
  /app/ml             (asr.py, nlp_classifier.py, image_analysis.py)
  requirements.txt
  main.py
/app_flutter                     (Flutter project, single codebase)
  /lib
    /screens/citizen            (submission, list, detail)
    /screens/staff               (officer, supervisor, admin — same app, role-gated)
    /services                    (api_client.dart, supabase_client.dart)
    /widgets
  pubspec.yaml   (add: supabase_flutter, http or dio, geolocator, record, flutter_map, provider or riverpod)
/docs                            (already contains CivicRoute_SRS.docx and BUILD_MANIFEST.md)

Requirements:
1. FastAPI app, CORS enabled, `/health` endpoint. Config module reads SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_JWT_SECRET, and DB URL from environment variables (.env.example included) — FastAPI connects to the same Postgres instance Supabase manages.
2. Async SQLAlchemy connection to the Supabase Postgres connection string, assuming PostGIS will be enabled in the next prompt.
3. Initialize supabase_flutter in the Flutter app (main.dart) pointing at the same Supabase project; a placeholder home screen only, no business logic yet.
4. No auth, no business logic yet in either app — scaffolding only. Do not implement a custom auth system anywhere; Supabase Auth is used exclusively (wired up starting Prompt 3).

Acceptance: `uvicorn main:app --reload` returns 200 on /health; `flutter run -d chrome` (or an emulator) launches the placeholder screen without errors.
```

---

## Prompt 2 — Data Model (SRS Section 7)

```
Implement the full data model exactly as specified in SRS Section 7 — open /docs/CivicRoute_SRS.docx Section 7 for the authoritative attribute list for each entity before writing models.

Entities: departments, jurisdictions, users, complaints, complaint_events, notifications.

Requirements:
1. SQLAlchemy models matching every attribute listed in Section 7, plus standard id/timestamps.
2. jurisdictions.boundary as a PostGIS Polygon column; complaints.location as a PostGIS Point column.
3. Alembic migration enabling the postgis extension on the Supabase Postgres instance, creating all tables, with indexes on complaints.status, complaints.department_id, complaints.jurisdiction_id.
4. Write basic Supabase Row-Level Security (RLS) policy stubs (as raw SQL migration files) for the complaints and complaint_events tables: officers/supervisors can only SELECT rows where jurisdiction_id matches their own user row's jurisdiction_id; citizens can only SELECT their own complaints. Leave a clear TODO comment where policies will be tightened once auth (Prompt 3) is wired up.
5. seed.py inserting: 5 departments (with sla_hours), 8 jurisdictions with realistic polygon boundaries for a sample city, 3 officer users + 2 supervisor users mapped to those jurisdictions, matching them to Supabase Auth users created via the Supabase Admin API (or documented manual step if that's simpler for local dev).
6. Pydantic Create/Read/Update schemas for every model.
7. Update BUILD_MANIFEST.md marking Section 7 entities as "implemented".

Acceptance: migration + seed leaves a queryable DB; `SELECT * FROM jurisdictions` returns 8 valid-geometry rows; RLS policies exist (even if not yet enforced end-to-end until Prompt 3).
```

---

## Prompt 3 — Auth (Supabase) + Complaint Intake API (FR-1.1 – FR-1.4)

```
Wire up Supabase Auth end-to-end, then build the complaint intake API on top of it, satisfying FR-1.1 through FR-1.4 (SRS Section 5.1) — quote each FR in a code comment above the relevant validation.

Part A — Auth:
1. FastAPI: add a dependency that extracts and validates the Supabase-issued JWT from the Authorization header (verify against SUPABASE_JWT_SECRET), resolving it to a users row. No custom session/token system — Supabase Auth is the only source of truth for identity.
2. Flutter: implement sign-in via supabase_flutter — phone/email OTP flow for citizens, email/password for staff — and store the resulting session for subsequent authenticated API calls.
3. Now tighten the RLS policy TODOs from Prompt 2 to use `auth.uid()` correctly against the users table.

Part B — Complaint Intake API:
POST /api/complaints (multipart/form-data): text (optional), image (optional file), audio (optional file), location_lat/location_lng (optional), address_text (optional). citizen_id comes from the validated JWT, not a client-supplied field.
1. FR-1.2: reject with 422 if none of text/image/audio present.
2. FR-1.3: accept either GPS coords or free-text address.
3. FR-1.4: create the complaint row with status="registered" and return complaint_id immediately; kick off processing via FastAPI BackgroundTasks (log-only placeholder for now).
4. Upload files directly to a Supabase Storage bucket (e.g. `complaint-media/{complaint_id}/...`) — not local disk, in any environment — and store the returned Storage path/URL on the complaint row.
5. GET /api/complaints/{id}, GET /api/complaints (scoped to the authenticated citizen via RLS + an explicit query filter), GET /api/complaints/{id}/timeline (empty for now, wired up fully by Prompt 9).

Acceptance: a Flutter test client (or curl with a real Supabase JWT) can sign in, POST a text complaint, and get back 201 + complaint_id; GET on that id shows status "registered"; an unauthenticated request is rejected.
```

---

## Prompt 4 — Module 4.1: Speech-to-Text

```
Open SRS Section 4.1 and implement its internal steps exactly as listed.

Create /backend/app/ml/asr.py wrapping faster-whisper (small/base multilingual model), function `transcribe(audio_path: str) -> {text, detected_language}`. The audio file is pulled from the Supabase Storage path stored on the complaint (download to a temp file for processing, then discard).

Requirements matching the SRS steps:
1. Validate audio format/duration/size before processing.
2. Run Whisper transcription.
3. Capture detected spoken language (English or Tamil) without auto-translating.
4. Wire into the background pipeline: if audio present, transcribe and store on complaints.transcribed_text plus the language tag.
5. Log a complaint_event "audio_transcribed" including a confidence indicator.
6. Write test_asr.py exercising a sample audio file (can use a local fixture file, doesn't need to hit Supabase Storage for the unit test).

Acceptance: test_asr.py prints a reasonable transcript + language code; a complaint submitted with audio shows transcribed_text populated and an "audio_transcribed" event in its timeline.
```

---

## Prompt 5 — Module 4.2: NLP Department Classification (FR-2.1 – FR-2.3)

```
Open SRS Section 4.2 and implement its pipeline step-by-step, satisfying FR-2.1, FR-2.2, and FR-2.3. Quote each FR above its corresponding code block.

Create /backend/app/services/nlp_classifier.py:
1. Normalize text; apply a Tamil-English civic-term lookup table (separate data file, easy to extend) for code-switched input.
2. Embed normalized text via sentence-transformers (MiniLM).
3. Maintain a FAISS index of curated reference phrases per department; classify by nearest-neighbor with a cosine-similarity confidence score.
4. If confidence >= 0.55: run a second FAISS match restricted to that department's subcategories.
5. FR-2.3: if confidence < 0.55, set status "needs_review" and route to an admin triage queue table instead of guessing.
6. Persist department_id, subcategory, confidence score.
7. Wire into the background pipeline: run on best available text (prefer raw_text, fall back to transcribed_text).
8. Unit tests: at least 10 sample complaints (English, Tamil-English code-switched) with expected department assertions, plus one low-confidence case asserting "needs_review".

Acceptance: unit tests pass; a complaint like "road la periya pothole irukku, romba dangerous" classifies to Roads with reasonable confidence; a nonsense/ambiguous complaint lands in needs_review.
```

---

## Prompt 6 — Module 4.3: Computer Vision (FR-2.4, FR-2.5)

```
Open SRS Section 4.3 and implement it exactly, satisfying FR-2.4 and FR-2.5.

Create /backend/app/ml/image_analysis.py using CLIP zero-shot classification against a fixed civic-issue label set (pothole, garbage pile, broken streetlight, pipe leak, overflowing drain, fallen tree, damaged electricity pole, irrelevant/unclear image). Images are pulled from the Supabase Storage path on the complaint.

Requirements:
1. Validate/flag unclear or irrelevant images using the "irrelevant/unclear" label.
2. Map top label + confidence to severity_hint (minor/moderate/severe) via a documented, tunable lookup table.
3. FR-2.5: cross-check the CV label against the Module 4.2 department result; if they disagree, log complaint_event "classification_conflict".
4. Persist label, confidence, severity_hint, conflict flag in a JSON column or side table.
5. Wire into the background pipeline: run when image present, after Module 4.2.
6. Test with 3 sample images (pothole, garbage, irrelevant photo) asserting sensible labels and correct flagging of the irrelevant one.

Acceptance: tests pass; a complaint with both a "water leak" text and a garbage-pile photo produces a classification_conflict event.
```

---

## Prompt 7 — Module 4.4: GIS Location Intelligence (FR-3.1 – FR-3.3)

```
Open SRS Section 4.4 and implement it exactly, satisfying FR-3.1, FR-3.2, FR-3.3.

Create /backend/app/services/gis_resolver.py:
1. If lat/lng given, use directly; else geocode address_text via an open geocoder (Nominatim/geopy), caching results by address string.
2. Run PostGIS ST_Contains against seeded jurisdiction polygons (in Supabase Postgres) to find the containing ward/zone.
3. FR-3.3: if no polygon contains the point, fall back to nearest jurisdiction centroid within a max radius and flag "jurisdiction_uncertain" for manual admin assignment.
4. Cross-reference the resolved ward with the department from Module 4.2: if that department has no ward-level office, escalate to the parent zone office.
5. Persist jurisdiction_id, resolution method, uncertainty flag.
6. Wire into the background pipeline after Module 4.3.
7. Unit tests: points inside seeded jurisdictions resolve correctly; one point clearly outside all boundaries exercises the fallback path.

Acceptance: tests pass; a complaint submitted with lat/lng inside seeded Ward 3 resolves jurisdiction_id to Ward 3; an out-of-bounds point gets flagged jurisdiction_uncertain.
```

---

## Prompt 8 — Module 4.5: Priority Scoring Engine (FR-4.1, FR-4.2)

```
Open SRS Section 4.5 and implement it exactly, satisfying FR-4.1 and FR-4.2. Fully deterministic — no LLM calls anywhere in this module.

Create /backend/app/services/priority_engine.py, function `compute_priority(complaint, related_complaints, cv_result) -> (score, label, breakdown)`:
1. Department base-weight from a config table.
2. Severity-keyword boost from a maintained keyword list.
3. CV severity_hint contribution (Module 4.3), if present.
4. FR-4.2: query open complaints of the same department within ~100m in the last 30 days (PostGIS ST_DWithin); if 3+, boost priority and link via shared cluster_id.
5. SLA time-decay boost if open longer than department SLA; mark "at_risk".
6. Sum into a 0-100 score, map to Low/Medium/High/Critical, store the full breakdown dict.
7. Wire into the pipeline after Module 4.4.
8. Unit tests: a routine complaint (Low), a complaint with danger keywords (High), a 3+ complaint cluster (High/Critical).

Acceptance: tests pass; breakdown dict clearly attributes points to specific factors; GET /api/complaints/{id} exposes the breakdown.
```

---

## Prompt 9 — Module 4.6: Routing Engine + Module 4.7: Workflow FSM (FR-4.3, FR-4.4, FR-5.1 – FR-5.5)

```
Open SRS Sections 4.6 and 4.7 and implement both together, satisfying FR-4.3, FR-4.4, and FR-5.1 through FR-5.5.

Part A — Workflow FSM (/backend/app/services/workflow_engine.py):
1. Define allowed transitions as an explicit table: registered->assigned (system), assigned->in_progress (officer: start_work), in_progress->resolved (officer: mark_resolved, requires evidence image + closing note per FR-5.2), resolved->closed (supervisor: approve, FR-5.3), resolved->in_progress (supervisor: reject), assigned/in_progress->escalated (system, on SLA breach, FR-5.4).
2. FR-5.1: reject any transition not in this table with a 409, regardless of caller.
3. FR-5.5: every transition writes an immutable complaint_events row.
4. Implement check_sla_breaches() (runnable via APScheduler/cron) auto-escalating overdue complaints.

Part B — Routing Engine (/backend/app/services/routing_engine.py):
1. Match officer by jurisdiction_id (Module 4.4) + department_id (Module 4.2); find their supervisor.
2. FR-4.4: compute sla_deadline = now + department.sla_hours, shortened for Critical priority via a configured multiplier.
3. Call the FSM to transition registered->assigned.
4. FR-4.3: create notification rows for officer, supervisor, and citizen simultaneously.
5. Refactor the full background task into an explicit, idempotent, retryable sequential pipeline: transcribe -> classify -> analyze_image -> resolve_gis -> compute_priority -> route.
6. POST /api/complaints/{id}/actions (officer actions, actor resolved from the validated JWT — not a client-supplied actor_id) and POST /api/complaints/{id}/approve (supervisor), both going through the FSM.

Acceptance: submitting a full complaint end-to-end reaches status "assigned" automatically with 3 notifications created; walking it through start_work -> mark_resolved -> approve reaches "closed"; an officer from the wrong jurisdiction (per their JWT-resolved user row) gets 403; an out-of-table transition gets 409; GET /api/complaints/{id}/timeline shows every step in order.
```

---

## Prompt 10 — Module 4.8: Real-Time Notifications via Supabase Realtime (FR-6.1)

```
Open SRS Section 4.8 carefully — this module now specifically relies on Supabase Realtime rather than a custom push layer. Do not build a WebSocket server.

Backend:
1. Ensure Realtime is enabled on the notifications table in Supabase (migration or documented dashboard step).
2. Continue writing notification rows exactly as already happening from Prompt 9 — no additional backend push logic is needed, Supabase Realtime handles delivery from the table itself.
3. PATCH /api/notifications/{id}/read to mark read (this UPDATE is what propagates as a Realtime event to the client).
4. GET /api/notifications to list a user's notifications with unread count (for initial load / fallback).

Flutter:
1. Using supabase_flutter, subscribe to the notifications table filtered to `user_id = current user's id` via `.stream()` or channel subscription.
2. Add a notification bell widget (usable in both the citizen app and the staff web views) showing unread count, a dropdown/panel of recent notifications, and marking them read on open (calling the PATCH endpoint).
3. Show a lightweight in-app toast/snackbar for high-priority events (assignment, SLA breach/escalation).

Acceptance: with two Flutter sessions running (different logged-in users), performing an action affecting one user's complaint causes a visible, near-instant notification in the other session's UI without a manual refresh or any custom WebSocket code.
```

---

## Prompt 11 — Module 4.9: Narrative Summary Generator

```
Open SRS Section 4.9 carefully — this is the ONLY module allowed to call a generative LLM, and only after every decision below it has already been finalized deterministically.

Create /backend/app/services/narrative_generator.py:
1. Gather already-finalized structured facts for a complaint: department, subcategory, priority breakdown, jurisdiction, current status, timeline.
2. Call a local LLM (Ollama llama3) with a constrained prompt: pass ONLY the structured facts, instruct it to phrase them as a short paragraph, explicitly instructing it not to introduce new facts.
3. Guardrail: after generation, check that no field value (department name, ward name, status word) appears that wasn't in the input structured facts; if mismatched, discard and fall back to a plain template sentence built directly from the structured facts (no LLM).
4. Add GET /api/complaints/{id}/summary returning this narrative.
5. Unit test asserting the guardrail rejects a deliberately fabricated fake LLM response (mock the LLM call, confirm fallback triggers).

Acceptance: GET /summary returns a coherent paragraph for a real complaint; the guardrail test confirms fabricated output is caught and replaced.
```

---

## Prompt 12 — Citizen Screens in Flutter (FR-6.2)

```
Build the citizen-facing screens in the Flutter app (/app_flutter/lib/screens/citizen), satisfying FR-6.2.

1. New Complaint screen: text field, image picker (image_picker package) with preview, audio recording (record package) or file picker, location via geolocator with a manual address text-field fallback. Submits multipart to POST /api/complaints using the authenticated Supabase session's access token as the Authorization header.
2. My Complaints screen: list of the citizen's own complaints (GET /api/complaints) with color-coded status chips.
3. Complaint Detail screen: full timeline (GET /timeline) rendered as a vertical stepper/timeline widget, current status, SLA countdown, and the narrative summary (GET /summary) shown as a plain-language recap.
4. Auth: sign-in/sign-up screens using supabase_flutter's OTP flow (phone or email) — no custom auth UI logic, delegate to Supabase Auth's client methods.
5. Mobile-first layout; keep the widget tree simple and reusable since staff screens (Prompt 13) will share some of these same widgets (status chips, timeline widget).

Acceptance: I can sign in, submit a complaint through the app with text + photo + device location, see it as "registered" in My Complaints, then watch it progress to "assigned" without touching the backend directly.
```

---

## Prompt 13 — Officer & Supervisor Screens in Flutter Web (FR-6.3)

```
Build the internal dashboards as Flutter Web screens in the same app (/app_flutter/lib/screens/staff), satisfying FR-6.3 (priority-breakdown transparency). Reuse the status-chip and timeline widgets from Prompt 12 rather than duplicating them.

1. Officer Queue screen: complaints assigned to the logged-in officer (role/jurisdiction resolved server-side from their JWT), sorted by priority then SLA deadline. Action buttons call POST /api/complaints/{id}/actions per the FSM from Prompt 9 (start_work, mark_resolved with evidence upload to Supabase Storage + note, request_more_info).
2. Supervisor Overview screen: cross-jurisdiction complaint list grouped by status; a "resolved, pending approval" queue with approve/reject buttons; an escalations panel; an analytics strip (open count, resolved this week, avg resolution time, escalation rate).
3. FR-6.3: both screens must show the priority_score breakdown (Module 4.5) in an expandable panel — not buried behind an admin-only view.
4. Role-gate these screens/routes based on the authenticated user's role (fetched once at login from the users table via Supabase, cached in app state — use provider or riverpod as set up in Prompt 1).
5. Build this to run well via `flutter run -d chrome` / `flutter build web`, since officers and supervisors are expected to use this on desktop browsers.

Acceptance: an officer sees only their jurisdiction's complaints correctly sorted; a supervisor can approve/reject from the queue; expanding any complaint shows its priority breakdown; a citizen-role login cannot reach these screens.
```

---

## Prompt 14 — Admin GIS Map Screen (Flutter Web)

```
Build the admin map dashboard described in SRS Section 8.2, as a Flutter Web screen (/app_flutter/lib/screens/staff/admin_map.dart).

1. Use flutter_map with OpenStreetMap tiles (no paid keys) to render jurisdiction boundary polygons, colored by open-complaint count or SLA-risk (fetch polygon GeoJSON from a new admin-only FastAPI endpoint that serializes the PostGIS geometries).
2. Plot complaint points as markers colored by priority, tappable to open the complaint detail screen (reuse from Prompt 12/13).
3. Filters: department, status, date range (simple dropdowns/date pickers driving a re-fetch).
4. Stats panel: total this month, top 3 departments by volume, top 3 wards by escalation rate (from a new admin analytics endpoint).
5. Role-gate to admin only.

Acceptance: the map renders all seeded jurisdiction boundaries and complaint points correctly on Flutter Web, and filters update the view; a non-admin user cannot reach this screen.
```

---

## Prompt 15 — Testing, Seed Scale, Deployment

```
Harden the system for evaluation/demo, and produce final traceability.

1. Expand seed.py to ~150 synthetic complaints spread across departments/wards/priorities/statuses/languages.
2. Integration test covering the full lifecycle end-to-end: submit -> pipeline completes -> assigned -> resolved -> closed, asserting the timeline has every expected event in order.
3. Rate limiting on POST /api/complaints.
4. docker-compose.yml bringing up the FastAPI backend + a local Postgres/PostGIS for offline dev (documented separately: how to point the same backend at a hosted Supabase project instead for the live demo, per SRS Section 2.6).
5. /docs/deployment.md covering: environment variables (including Supabase project URL/keys), migrations, the background worker caveat (BackgroundTasks -> Celery+Redis before real production use), and Flutter build/run instructions for both mobile and web targets.
6. /docs/known_limitations.md separating genuine production concerns (geocoding accuracy, single-region jurisdiction data, no real SMS integration) from what's fine for an academic/portfolio deployment.
7. Update /docs/BUILD_MANIFEST.md marking every FR-x.x and module 4.x as "implemented ✅" with a pointer to the file/test that satisfies it.

Acceptance: `docker-compose up` gives a working backend from a clean machine against local Postgres/PostGIS; `flutter run` and `flutter build web` both succeed; integration tests pass; BUILD_MANIFEST.md shows 100% of FR-x.x and module 4.x checked off.
```

---

## Notes

- Prompts 2, 4-9, 11 are unchanged from the original build guide — they're backend/FastAPI logic that doesn't depend on frontend framework or auth provider choice, so they carry over directly.
- Prompts 1, 3, 10, 12-14 are the ones rewritten for this stack: scaffolding now sets up Flutter + Supabase client init instead of Next.js; intake now uses Supabase Storage + Supabase Auth JWTs instead of local disk + a stub header; notifications now ride on Supabase Realtime instead of a custom WebSocket; and the three frontend prompts are Flutter screens (one codebase, role-gated) instead of separate Next.js pages.
- Because Flutter Web serves the staff dashboards from the same codebase as the citizen mobile app, Prompts 13 and 14 explicitly tell the agent to reuse widgets from Prompt 12 rather than re-implement status chips/timelines — worth keeping an eye on so the shared-widget intent doesn't get lost as the app grows.
