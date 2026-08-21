"""
SecureCloud Platform - Flask Application Factory
"""
from flask import Flask
from app.config import Config
from app.extensions import init_extensions
from app.routes import register_blueprints
from app.monitoring import init_monitoring


def create_app(config_class=Config):
    """Application factory pattern"""
    app = Flask(__name__)
    app.config.from_object(config_class)

    init_extensions(app)
    register_blueprints(app)
    init_monitoring(app)

    return app