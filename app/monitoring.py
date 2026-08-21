"""
SecureCloud Platform - Application Monitoring & Telemetry
"""
import os
import time
import structlog
from flask import Flask, jsonify, request, g
from app.config import get_settings

logger = structlog.get_logger()


def init_monitoring(app: Flask) -> None:
    """Initialize application monitoring"""
    settings = get_settings()

    if not settings.enable_monitoring:
        logger.info("monitoring_disabled")
        return

    # Initialize Azure Monitor OpenTelemetry if configured
    if settings.app_insights_connection_string:
        try:
            from azure.monitor.opentelemetry import configure_azure_monitor
            configure_azure_monitor(
                connection_string=settings.app_insights_connection_string
            )
            logger.info("azure_monitor_initialized")
        except Exception as e:
            logger.warning("azure_monitor_init_failed", error=str(e))

    # Request logging middleware
    @app.before_request
    def log_request():
        g.start_time = time.time()
        logger.info(
            "request_started",
            method=request.method,
            path=request.path,
            remote_addr=request.remote_addr,
            user_agent=request.headers.get("User-Agent"),
            request_id=request.headers.get("X-Request-ID")
        )

    @app.after_request
    def log_response(response):
        if hasattr(g, "start_time"):
            duration = time.time() - g.start_time
            logger.info(
                "request_completed",
                method=request.method,
                path=request.path,
                status_code=response.status_code,
                duration_ms=round(duration * 1000, 2)
            )
        return response

    # Error handler
    @app.errorhandler(Exception)
    def handle_exception(e):
        logger.error(
            "unhandled_exception",
            error=str(e),
            path=request.path,
            method=request.method,
            exc_info=True
        )
        return jsonify({"error": "Internal server error"}), 500

    logger.info("monitoring_initialized")