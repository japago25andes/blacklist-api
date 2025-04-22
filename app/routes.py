from flask import Blueprint, request, jsonify, current_app
from .models import BlacklistedEmail
from . import db

bp = Blueprint('main', __name__)

@bp.route('/blacklists', methods=['POST'])
def add_to_blacklist():
    # Validar token estático
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith("Bearer "):
        return jsonify({"error": "Token de autorización requerido"}), 401

    token = auth_header.split(" ")[1]
    if token != current_app.config['AUTH_TOKEN']:
        return jsonify({"error": "Token inválido"}), 403

    # Obtener datos del JSON
    data = request.get_json()
    email = data.get('email', '').strip().lower()
    app_uuid = data.get('app_uuid')
    blocked_reason = data.get('blocked_reason', None)

    if not email or not app_uuid:
        return jsonify({"error": "Los campos 'email' y 'app_uuid' son obligatorios"}), 400

    # Capturar IP del cliente
    ip_address = request.remote_addr or '0.0.0.0'

    # Guardar en base de datos
    new_entry = BlacklistedEmail(
        email=email,
        app_uuid=app_uuid,
        blocked_reason=blocked_reason,
        ip_address=ip_address
    )

    db.session.add(new_entry)
    db.session.commit()

    return jsonify({"message": "Email agregado a la lista negra exitosamente"}), 201

@bp.route('/blacklists/<string:email>', methods=['GET'])
def check_blacklist(email):
    # Validar token estático
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith("Bearer "):
        return jsonify({"error": "Token de autorización requerido"}), 401

    token = auth_header.split(" ")[1]
    if token != current_app.config['AUTH_TOKEN']:
        return jsonify({"error": "Token inválido"}), 403

    # Buscar email en la base de datos
    entry = BlacklistedEmail.query.filter_by(email=email.strip().lower()).first()

    if entry:
        return jsonify({
            "is_blacklisteds": True,
            "blocked_reason": entry.blocked_reason
        }), 200
    else:
        return jsonify({
            "is_blacklisted": False
        }), 200

@bp.route("/health")
def health():
    return "OK", 200
