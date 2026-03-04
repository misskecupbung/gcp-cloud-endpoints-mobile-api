"""Mobile API backend with Firestore."""

import os
import logging
import json
from datetime import datetime, timezone
from functools import wraps
from flask import Flask, request, jsonify, g
from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from google.cloud import firestore
from google.cloud.logging import Client as LoggingClient
from werkzeug.exceptions import HTTPException

# Setup structured logging for Cloud Logging
if os.environ.get("GAE_ENV"):
    logging_client = LoggingClient()
    logging_client.setup_logging()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app, resources={r"/api/*": {
    "origins": os.environ.get("ALLOWED_ORIGINS", "*").split(","),
    "methods": ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    "allow_headers": ["Content-Type", "Authorization"]
}})

# Rate limiting: 100 requests per minute per IP
limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["100 per minute"],
    storage_uri="memory://"
)

db = firestore.Client()
USERS_COLLECTION = "users"


def log_request():
    """Log request details."""
    logger.info(json.dumps({
        "type": "request",
        "method": request.method,
        "path": request.path,
        "ip": request.headers.get("X-Forwarded-For", request.remote_addr),
        "user_agent": request.user_agent.string
    }))


def require_json(*fields):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            if not request.is_json:
                return jsonify({"error": "Content-Type must be application/json"}), 400
            data = request.get_json()
            missing = [field for field in fields if field not in data]
            if missing:
                return jsonify({"error": f"Missing fields: {', '.join(missing)}"}), 400
            return f(*args, **kwargs)
        return wrapper
    return decorator


def validate_email(email):
    """Basic email validation."""
    return email and "@" in email and "." in email.split("@")[-1]


@app.before_request
def before_request():
    g.start_time = datetime.now(timezone.utc)
    log_request()


@app.after_request
def after_request(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Request-Id"] = request.headers.get("X-Cloud-Trace-Context", "")

    duration = (datetime.now(timezone.utc) - g.start_time).total_seconds()
    logger.info(json.dumps({
        "type": "response",
        "status": response.status_code,
        "duration_ms": round(duration * 1000, 2)
    }))
    return response


# Health endpoints

@app.route("/api/v1/health")
def health():
    try:
        db.collection(USERS_COLLECTION).limit(1).get()
        db_status = "connected"
    except Exception as e:
        logger.error(f"Database health check failed: {e}")
        db_status = "disconnected"

    status = "healthy" if db_status == "connected" else "degraded"
    code = 200 if status == "healthy" else 503

    return jsonify({
        "status": status,
        "service": "mobile-api",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": os.environ.get("GAE_VERSION", "1.0.0"),
        "database": db_status
    }), code


@app.route("/api/v1/version")
def version():
    return jsonify({
        "api_version": "v1",
        "build_version": os.environ.get("GAE_VERSION", "1.0.0"),
        "environment": os.environ.get("GAE_ENV", "development")
    })


# Users endpoints

@app.route("/api/v1/users")
def list_users():
    try:
        limit = min(int(request.args.get("limit", 10)), 100)
        offset = int(request.args.get("offset", 0))
    except ValueError:
        return jsonify({"error": "Invalid pagination parameters"}), 400

    query = db.collection(USERS_COLLECTION).order_by("created_at", direction=firestore.Query.DESCENDING)
    docs = list(query.stream())
    total = len(docs)
    paginated = docs[offset:offset + limit]

    users = []
    for doc in paginated:
        user = doc.to_dict()
        user["id"] = doc.id
        users.append(user)

    return jsonify({
        "users": users,
        "pagination": {
            "total": total,
            "limit": limit,
            "offset": offset,
            "has_more": offset + limit < total
        }
    })


@app.route("/api/v1/users", methods=["POST"])
@require_json("name", "email")
def create_user():
    data = request.get_json()

    if not validate_email(data["email"]):
        return jsonify({"error": "Invalid email format"}), 400

    existing = db.collection(USERS_COLLECTION).where("email", "==", data["email"]).limit(1).get()
    if list(existing):
        return jsonify({"error": "Email already exists"}), 409

    now = datetime.now(timezone.utc).isoformat()
    user = {
        "name": data["name"].strip(),
        "email": data["email"].lower().strip(),
        "device": data.get("device"),
        "push_token": data.get("push_token"),
        "created_at": now,
        "updated_at": now
    }

    doc_ref = db.collection(USERS_COLLECTION).add(user)
    user["id"] = doc_ref[1].id

    logger.info(json.dumps({"type": "user_created", "user_id": user["id"]}))
    return jsonify({"message": "User created", "user": user}), 201


@app.route("/api/v1/users/<user_id>")
def get_user(user_id):
    doc = db.collection(USERS_COLLECTION).document(user_id).get()
    if not doc.exists:
        return jsonify({"error": "User not found"}), 404

    user = doc.to_dict()
    user["id"] = doc.id
    return jsonify({"user": user})


@app.route("/api/v1/users/<user_id>", methods=["PUT"])
def update_user(user_id):
    if not request.is_json:
        return jsonify({"error": "Content-Type must be application/json"}), 400

    doc_ref = db.collection(USERS_COLLECTION).document(user_id)
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({"error": "User not found"}), 404

    data = request.get_json()
    updates = {}

    if "email" in data:
        if not validate_email(data["email"]):
            return jsonify({"error": "Invalid email format"}), 400
        existing = db.collection(USERS_COLLECTION).where("email", "==", data["email"].lower()).limit(1).get()
        for e in existing:
            if e.id != user_id:
                return jsonify({"error": "Email already in use"}), 409
        updates["email"] = data["email"].lower().strip()

    if "name" in data:
        updates["name"] = data["name"].strip()
    if "device" in data:
        updates["device"] = data["device"]
    if "push_token" in data:
        updates["push_token"] = data["push_token"]

    if updates:
        updates["updated_at"] = datetime.now(timezone.utc).isoformat()
        doc_ref.update(updates)

    user = doc_ref.get().to_dict()
    user["id"] = user_id
    return jsonify({"message": "User updated", "user": user})


@app.route("/api/v1/users/<user_id>", methods=["DELETE"])
def delete_user(user_id):
    doc_ref = db.collection(USERS_COLLECTION).document(user_id)
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({"error": "User not found"}), 404

    user = doc.to_dict()
    user["id"] = user_id
    doc_ref.delete()

    logger.info(json.dumps({"type": "user_deleted", "user_id": user_id}))
    return jsonify({"message": "User deleted", "user": user})


# Device endpoints

@app.route("/api/v1/devices/register", methods=["POST"])
@require_json("user_id", "device_type", "push_token")
def register_device():
    data = request.get_json()

    if data["device_type"] not in ["ios", "android"]:
        return jsonify({"error": "device_type must be 'ios' or 'android'"}), 400

    doc_ref = db.collection(USERS_COLLECTION).document(data["user_id"])
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({"error": "User not found"}), 404

    doc_ref.update({
        "device": data.get("device_name", data["device_type"]),
        "device_type": data["device_type"],
        "push_token": data["push_token"],
        "updated_at": datetime.now(timezone.utc).isoformat()
    })

    logger.info(json.dumps({
        "type": "device_registered",
        "user_id": data["user_id"],
        "device_type": data["device_type"]
    }))

    return jsonify({
        "message": "Device registered",
        "user_id": data["user_id"],
        "device_type": data["device_type"]
    })


@app.route("/api/v1/devices/unregister", methods=["POST"])
@require_json("user_id")
def unregister_device():
    data = request.get_json()

    doc_ref = db.collection(USERS_COLLECTION).document(data["user_id"])
    doc = doc_ref.get()
    if not doc.exists:
        return jsonify({"error": "User not found"}), 404

    doc_ref.update({
        "push_token": None,
        "updated_at": datetime.now(timezone.utc).isoformat()
    })

    return jsonify({"message": "Device unregistered", "user_id": data["user_id"]})


# Error handlers

@app.errorhandler(HTTPException)
def handle_http_exception(e):
    logger.warning(json.dumps({
        "type": "http_error",
        "code": e.code,
        "description": e.description
    }))
    return jsonify({"error": e.description}), e.code


@app.errorhandler(Exception)
def handle_exception(e):
    logger.exception(f"Unhandled exception: {e}")
    return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=os.environ.get("GAE_ENV") is None)
