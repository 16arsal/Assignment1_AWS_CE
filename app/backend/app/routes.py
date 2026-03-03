from datetime import datetime, timezone
import platform

from flask import Blueprint, current_app, jsonify

api_bp = Blueprint("api", __name__)


def _utc_now_iso():
    return datetime.now(timezone.utc).isoformat()


def _simulate_db_check():
    return current_app.config.get("DB_READY", True)


@api_bp.get("/")
def root():
    return jsonify({"service": "backend", "status": "running"})


@api_bp.get("/health")
def health():
    # Liveness probe: confirms process is serving HTTP.
    return jsonify({"check": "liveness", "status": "healthy", "timestamp": _utc_now_iso()})


@api_bp.get("/ready")
def ready():
    # Readiness probe: in AWS this can gate traffic behind an ALB target group.
    db_ready = _simulate_db_check()
    if not db_ready:
        return (
            jsonify(
                {
                    "check": "readiness",
                    "status": "not_ready",
                    "details": {"database": "unavailable"},
                    "timestamp": _utc_now_iso(),
                }
            ),
            503,
        )

    return jsonify(
        {
            "check": "readiness",
            "status": "ready",
            "details": {"database": "reachable"},
            "timestamp": _utc_now_iso(),
        }
    )


@api_bp.get("/api/hello")
def hello():
    return jsonify(
        {
            "message": "Hello from Flask backend 🚀",
            "service": current_app.config["SERVICE_NAME"],
            "timestamp": _utc_now_iso(),
        }
    )


@api_bp.get("/api/info")
def info():
    return jsonify(
        {
            "service": current_app.config["SERVICE_NAME"],
            "version": current_app.config["SERVICE_VERSION"],
            "environment": current_app.config["FLASK_ENV"],
            "runtime": "flask",
            "python": platform.python_version(),
            "timestamp": _utc_now_iso(),
        }
    )
