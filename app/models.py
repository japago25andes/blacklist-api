from . import db
from datetime import datetime, timezone

class BlacklistedEmail(db.Model):
    __tablename__ = 'blacklisted_emails'

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), nullable=False)
    app_uuid = db.Column(db.String(36), nullable=False)
    blocked_reason = db.Column(db.String(255), nullable=True)
    ip_address = db.Column(db.String(45), nullable=False)  # IPv6 compatible
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

