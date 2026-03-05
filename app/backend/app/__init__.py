import logging

from flask import Flask
from flask_cors import CORS

from .config import Config


def create_app(config_class=Config):
    """Application factory keeps the app ready for EC2 and WSGI servers."""
    app = Flask(__name__)
    app.config.from_object(config_class)

    _configure_logging(app)

    # CORS is configurable so frontend origin can be restricted in EC2.
    CORS(app, resources={r"/*": {"origins": app.config["ALLOWED_ORIGINS"]}})

    from .routes import api_bp

    app.register_blueprint(api_bp)
    app.register_blueprint(api_bp, url_prefix="/api", name="api_prefixed")
    app.logger.info("Backend application initialized")
    return app


def _configure_logging(app):
    log_level = logging.DEBUG if app.config.get("FLASK_ENV") == "development" else logging.INFO
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    )
    app.logger.setLevel(log_level)
