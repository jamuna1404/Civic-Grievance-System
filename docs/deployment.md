# Deployment & Environment Configuration Guide

This document outlines the environment configuration, database migrations, background worker caveats, and Flutter compilation steps required to build and deploy the Civic Grievance System.

---

## 1. Environment Configuration

The backend is configured via standard environment variables. Create a `.env` file in the `/backend` folder using the following schema:

```env
# Database Credentials
# For local dev via Docker Compose:
DATABASE_URL=postgresql+asyncpg://postgres:postgres@db:5432/civic

# Supabase Configurations
SUPABASE_URL=https://<your-project-id>.supabase.co
SUPABASE_KEY=<your-anon-public-key>
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>

# JWT Security
# Must match the JWT secret key of your Supabase project (from Settings -> API -> JWT Secret)
# to verify citizen tokens locally.
JWT_SECRET=<your-supabase-jwt-secret-key>
```

### Switching from Local PostgreSQL to Hosted Supabase
To direct the backend to a live hosted Supabase database instead of the offline local Postgres container:
1. Obtain the database connection string from your Supabase Dashboard: **Project Settings -> Database -> Connection string -> Session (port 5432) or Transaction (port 6543)**.
2. Update the `DATABASE_URL` in `.env` to point to Supabase:
   `DATABASE_URL=postgresql+asyncpg://postgres.<your-project-id>:<your-password>@aws-0-us-east-1.pooler.supabase.com:5432/postgres`
3. Restart the backend service.

---

## 2. Database Migrations

Database tables can be created automatically using the database seeding script, or tracked incrementally via Alembic.

### Running Migrations Manually
If you are modifying models, execute the following from the `/backend` directory:
```bash
# Auto-generate revision script
alembic revision --autogenerate -m "Add new columns"

# Apply migrations to database
alembic upgrade head
```

---

## 3. Background Processing Queue Caveat

> [!WARNING]
> The current background processing pipeline uses FastAPI's built-in `BackgroundTasks` library.

### Limitations of `BackgroundTasks`
- **In-Memory**: Tasks are stored in memory; if the FastAPI server restarts, all pending complaints in the pipeline are lost.
- **Single-Process**: Background task executions share resource threads with API request processing, which can degrade web request latency under high volumes of speech-to-text or CLIP analysis.

### Production Alternative: Celery + Redis
For real-world production setups:
1. Install **Celery** on the FastAPI backend.
2. Spin up a **Redis** or **RabbitMQ** service container to act as a durable message broker.
3. Decouple pipeline tasks into Celery tasks (`@celery.task`) run by dedicated Celery workers, ensuring high availability, backpressure management, and job persistence.

---

## 4. Flutter Build & Run Instructions

Ensure Flutter SDK is installed and run `flutter doctor` to verify environment paths.

### Running Client App (Mobile & Web)
From the `/app_flutter` directory, run:

```bash
# Run web client on local Chrome browser (staff dashboards)
flutter run -d chrome --web-port=8080

# Run mobile citizen client on connected Android simulator/device
flutter run -d emulator-5554

# Run mobile citizen client on iOS simulator
flutter run -d iPhone
```

### Compiling Production Bundles
To compile final optimized outputs for staging/deployment:

```bash
# Compile optimized HTML/JS/WASM bundle for web deployment
flutter build web --release

# Compile APK bundle for Android
flutter build apk --release

# Compile archive for iOS App Store
flutter build ios --release
```
