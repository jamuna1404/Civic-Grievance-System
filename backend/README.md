# CivicRoute — Backend (FastAPI)

Skeleton API for CivicRoute. Routers are wired but empty; business logic
lands in later prompts.

## Structure

```
app/
  main.py                 # FastAPI app, CORS, router wiring, /health
  core/
    config.py             # env-backed Settings (pydantic-settings)
    supabase_client.py    # Supabase client singleton (get_supabase())
  routers/
    auth.py               # /auth      (empty)
    citizen.py            # /citizen   (empty)
    officer.py            # /officer   (empty)
    complaints.py         # /complaints(empty)
```

## Setup

```bash
python -m venv .venv
# Windows PowerShell:  .venv\Scripts\Activate.ps1
# bash:                source .venv/Scripts/activate
pip install -r requirements.txt
cp .env.example .env   # then fill in SUPABASE_URL / SUPABASE_KEY
```

## Run

```bash
uvicorn app.main:app --reload
```

- Health check: `GET http://localhost:8000/health`
- Interactive docs: `http://localhost:8000/docs`
