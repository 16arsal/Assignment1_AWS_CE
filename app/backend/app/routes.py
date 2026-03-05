from datetime import datetime, timezone
import html
import platform
import re

import requests
from flask import Blueprint, current_app, jsonify
from requests import RequestException

api_bp = Blueprint("api", __name__)
TVMAZE_SCHEDULE_URL = "https://api.tvmaze.com/schedule"


def _utc_now_iso():
    return datetime.now(timezone.utc).isoformat()


def _simulate_db_check():
    return current_app.config.get("DB_READY", True)


def _clean_summary(summary):
    if not summary:
        return None
    summary_without_tags = re.sub(r"<[^>]*>", "", summary)
    cleaned = html.unescape(summary_without_tags).strip()
    return cleaned or None


def _to_university_event(schedule_item):
    show = schedule_item.get("show") or {}
    network = show.get("network") or {}
    web_channel = show.get("webChannel") or {}
    image_info = show.get("image") or {}

    return {
        "title": show.get("name") or schedule_item.get("name") or "Untitled Event",
        "date": schedule_item.get("airdate") or show.get("premiered"),
        "venue": network.get("name") or web_channel.get("name") or show.get("type") or "TBA",
        "description": _clean_summary(show.get("summary")),
        "image": image_info.get("original") or image_info.get("medium"),
    }


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


@api_bp.get("/hello")
def hello():
    return jsonify(
        {
            "message": "Hello from Flask backend 🚀",
            "service": current_app.config["SERVICE_NAME"],
            "timestamp": _utc_now_iso(),
        }
    )


@api_bp.get("/info")
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


@api_bp.get("/events")
def events():
    external_api_url = current_app.config.get("EVENTS_API_URL", TVMAZE_SCHEDULE_URL)
    timeout_seconds = current_app.config.get("EVENTS_API_TIMEOUT", 8)

    try:
        response = requests.get(external_api_url, timeout=timeout_seconds)
        response.raise_for_status()
        payload = response.json()
    except RequestException as exc:
        current_app.logger.exception("Failed to fetch events from external API: %s", exc)
        return (
            jsonify(
                {
                    "events": [],
                    "error": "Failed to fetch events from external API",
                    "source": external_api_url,
                }
            ),
            502,
        )
    except ValueError as exc:
        current_app.logger.exception("External API returned invalid JSON: %s", exc)
        return (
            jsonify(
                {
                    "events": [],
                    "error": "External API returned invalid JSON",
                    "source": external_api_url,
                }
            ),
            502,
        )

    if not isinstance(payload, list):
        current_app.logger.error("External API payload is not a list")
        return (
            jsonify(
                {
                    "events": [],
                    "error": "External API response format is invalid",
                    "source": external_api_url,
                }
            ),
            502,
        )

    events_payload = [_to_university_event(item) for item in payload if isinstance(item, dict)]
    return jsonify({"events": events_payload})
