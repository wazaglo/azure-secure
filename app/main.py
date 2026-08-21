"""
SecureCloud Platform - Application Entry Point
"""
import os
import sys
import structlog
from app import create_app
from app.config import get_settings
from app.database import db_manager

logger = structlog.get_logger()

# Create Flask app
app = create_app()

# Initialize database on startup
@app.before_request
def initialize_db():
    """Initialize database connection pool on first request"""
    if not hasattr(app, "_db_initialized"):
        try:
            db_manager.initialize()
            app._db_initialized = True
            logger.info("database_initialized_on_startup")
        except Exception as e:
            logger.error("database_init_failed", error=str(e))
            # Don't raise - let health checks handle it


@app.teardown_appcontext
def close_db(error):
    """Close database connections on app teardown"""
    if error:
        logger.error("request_error", error=str(error))


if __name__ == "__main__":
    settings = get_settings()

    logger.info(
        "starting_application",
        environment=settings.environment,
        host=settings.host,
        port=settings.port
    )

    # Run with Gunicorn in production, Flask dev server in development
    if settings.environment == "production":
        logger.warning("running_with_flask_dev_server_in_production")
        app.run(host=settings.host, port=settings.port, debug=settings.debug)
    else:
        app.run(host=settings.host, port=settings.port, debug=settings.debug)