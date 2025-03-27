import os

class Config:
    SQLALCHEMY_DATABASE_URI = os.getenv("DATABASE_URL", "sqlite:///fallback.db")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    AUTH_TOKEN = os.getenv("AUTH_TOKEN", "default_token")
