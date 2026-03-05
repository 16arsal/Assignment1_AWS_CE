from app import create_app

# Exposes `app` for Gunicorn: `gunicorn -w 4 -b 0.0.0.0:5000 run:app`
app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=app.config.get("PORT", 5000))
