from app import create_app

# Exposes `app` for future Gunicorn usage: `gunicorn run:app`
app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=app.config.get("PORT", 5000))
