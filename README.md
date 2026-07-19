# CivicRoute

A civic complaint app for Chennai — residents report civic issues and each
complaint is routed to the responsible ward officer.

- **Frontend:** Flutter (`frontend/`)
- **Backend:** FastAPI (`backend/`)
- **Data:** Supabase (Postgres) — schemas in `civicroute_*.sql`

> Status: **Scaffolding + design system.** Auth, complaint, and officer
> features are not built yet.

## Structure

```
frontend/   Flutter app (theme system, shared widgets, go_router, Riverpod)
backend/    FastAPI skeleton (empty routers + Supabase client singleton)
doc/        Project documentation
*.sql       Supabase schema files
```

## Frontend

```bash
cd frontend
flutter pub get
flutter run
```

The app currently opens on a **theme showcase screen** — a temporary review
surface with a Light / Dark / System toggle and sample cards, buttons, inputs,
and type so both themes can be verified. See `frontend/lib/core/theme/` for the
design system.

## Backend

See [`backend/README.md`](backend/README.md).
