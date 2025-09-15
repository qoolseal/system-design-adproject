from flask import Flask
import os

app = Flask(__name__)

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.get("/")
def index():
    db_url = os.environ.get("DATABASE_URL", "not set")
    return {"app": "ads-demo", "db_url": db_url}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)