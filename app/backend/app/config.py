import os


class Config:
    # Environment variables map directly to EC2 runtime config (systemd/user-data).
    FLASK_ENV = os.getenv("FLASK_ENV", "development")
    PORT = int(os.getenv("PORT", "5000"))

    SERVICE_NAME = os.getenv("SERVICE_NAME", "backend")
    SERVICE_VERSION = os.getenv("SERVICE_VERSION", "1.0.0")
    ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*")

    # Simulates a dependency check used by ALB/Auto Scaling readiness probes.
    DB_READY = os.getenv("DB_READY", "true").lower() in {"1", "true", "yes"}
