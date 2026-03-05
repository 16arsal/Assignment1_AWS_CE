# Assignment 1 - AWS Cloud Engineering Full-Stack App

This project is a production-style Flask + React application scaffold prepared for AWS EC2 deployment.
It is structured for maintainability, health checks, readiness checks, and Gunicorn-based production serving.

## Tech Stack
- Backend: Flask, Flask-CORS, Gunicorn, Requests
- Frontend: Vite + React
- Deployment target: AWS EC2 behind ALB (no Docker)

## Project Structure
```text
Assignment1_AWS_CE/
|-- app/
|   |-- backend/
|   |   |-- app/
|   |   |   |-- __init__.py      # Flask app factory + CORS + logging
|   |   |   |-- config.py        # Centralized environment config
|   |   |   `-- routes.py        # Blueprint routes and health/readiness endpoints
|   |   |-- .env.example
|   |   |-- .gitignore
|   |   |-- requirements.txt
|   |   `-- run.py               # Entrypoint + Gunicorn WSGI app export
|   `-- frontend/
|       |-- src/
|       |   |-- api/
|       |   |   `-- client.js    # API client abstraction using VITE_API_BASE_URL
|       |   |-- components/
|       |   |   `-- StatusCard.jsx
|       |   |-- App.css
|       |   |-- App.jsx
|       |   |-- index.css
|       |   `-- main.jsx
|       |-- .env.example
|       |-- .gitignore
|       |-- index.html
|       |-- package.json
|       `-- vite.config.js
|-- infra/
`-- README.md
```

## Backend API Endpoints
Base URL (local): `http://localhost:5000`

- `GET /`
  - Returns service status
  - Response: `{ "service": "backend", "status": "running" }`

- `GET /health`
  - Liveness check (for process/instance health)

- `GET /ready`
  - Readiness check (simulated DB dependency check)
  - Returns `503` when not ready

- `GET /api/hello`
  - Structured hello response with UTC timestamp

- `GET /api/info`
  - Environment and service metadata

- `GET /events` and `GET /api/events`
  - Fetches schedule data from a public Open API (`https://api.tvmaze.com/schedule`)
  - Transforms it into UniEvent-compatible event objects:
    - `title`
    - `date`
    - `venue`
    - `description`
    - `image`

## Environment Configuration
### Backend (`app/backend/.env.example`)
- `FLASK_ENV=development`
- `PORT=5000`
- `SERVICE_NAME=backend`
- `SERVICE_VERSION=1.0.0`
- `DB_READY=true`
- `ALLOWED_ORIGINS=http://localhost:5173`

### Frontend (`app/frontend/.env.example`)
- `VITE_API_BASE_URL=http://localhost:5000`

## Local Dev Run Instructions
### 1) Run backend
```powershell
cd app/backend
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
python run.py
```

### 2) Run frontend
```powershell
cd app/frontend
npm install
npm run dev
```

Frontend default URL: `http://localhost:5173`

## Production Run Instructions (EC2)
From `app/backend`:

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
gunicorn -w 4 -b 0.0.0.0:5000 run:app
```

## AWS EC2 Deployment Readiness Notes
- Backend binds to `0.0.0.0` and configurable `PORT` for EC2 runtime compatibility.
- App factory pattern keeps initialization clean and testable for cloud deployments.
- Health and readiness endpoints are ready for ALB target group checks.
- `run.py` exposes `app` directly for Gunicorn:
  - `gunicorn -w 4 -b 0.0.0.0:5000 run:app`
- CORS origin is configurable via environment variables.

## External Event API Integration
- Public API used: `https://api.tvmaze.com/schedule`
- Why this API was chosen:
  - Free and public endpoint
  - No authentication key required
  - Returns structured JSON suitable for backend transformation
- Transformation into "University Events":
  - `title`: from `show.name` (fallback: schedule item name)
  - `date`: from `airdate` (fallback: `show.premiered`)
  - `venue`: from `show.network.name` or `show.webChannel.name` (fallbacks applied)
  - `description`: from `show.summary` after stripping HTML tags
  - `image`: from `show.image.original` or `show.image.medium`
- Endpoint availability:
  - `/events`
  - `/api/events`
  These both work because the same Flask blueprint is registered once at root and once with `/api`.

### Example curl Commands
```bash
curl http://localhost:5000/api/events
curl http://<ALB-DNS>/api/events
```

## Submission Notes
- No Docker is used, as required.
- Dependencies are intentionally minimal (`flask`, `flask-cors`, `gunicorn`, `requests`) for clarity and grading.
