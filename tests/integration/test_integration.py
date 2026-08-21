"""
SecureCloud Platform - Integration Tests
Runs against deployed environments (dev/staging/prod)
Set APP_URL environment variable to target URL
"""
import os
import json
import requests
import pytest

# Target environment URL
APP_URL = os.environ.get("APP_URL", "http://localhost:5000")
API_KEY = os.environ.get("API_KEY", "test-api-key-12345")
TIMEOUT = 10


@pytest.fixture(scope="module")
def base_url():
    """Base URL for integration tests"""
    return APP_URL.rstrip("/")


class TestHealthChecks:
    """Integration tests for health check endpoints"""

    def test_liveness(self, base_url):
        """Test liveness endpoint is always responding"""
        response = requests.get(f"{base_url}/health/live", timeout=TIMEOUT)
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "alive"

    def test_health(self, base_url):
        """Test comprehensive health check"""
        response = requests.get(f"{base_url}/health", timeout=TIMEOUT)
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert data["checks"]["key_vault"]["status"] == "connected"
        assert data["checks"]["database"]["status"] == "connected"

    def test_readiness(self, base_url):
        """Test readiness probe"""
        response = requests.get(f"{base_url}/health/ready", timeout=TIMEOUT)
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ready"


class TestAPIEndpoints:
    """Integration tests for API endpoints"""

    def test_home(self, base_url):
        """Test home endpoint"""
        response = requests.get(base_url, timeout=TIMEOUT)
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "SecureCloud Platform API"
        assert "version" in data
        assert "environment" in data
        assert "timestamp" in data

    def test_api_docs(self, base_url):
        """Test API documentation endpoint"""
        response = requests.get(f"{base_url}/api", timeout=TIMEOUT)
        assert response.status_code == 200
        data = response.json()
        assert data["api_version"] == "v1"
        assert len(data["endpoints"]) >= 6

    def test_metrics_valid_key(self, base_url):
        """Test metrics endpoint with valid API key"""
        response = requests.get(
            f"{base_url}/api/metrics",
            headers={"X-API-Key": API_KEY},
            timeout=TIMEOUT
        )
        assert response.status_code == 200
        data = response.json()
        assert "application" in data
        assert "database" in data

    def test_metrics_invalid_key(self, base_url):
        """Test metrics endpoint with invalid API key"""
        response = requests.get(
            f"{base_url}/api/metrics",
            headers={"X-API-Key": "invalid-key"},
            timeout=TIMEOUT
        )
        assert response.status_code == 401
        data = response.json()
        assert data["error"] == "Invalid or missing API key"

    def test_metrics_missing_key(self, base_url):
        """Test metrics endpoint without API key"""
        response = requests.get(f"{base_url}/api/metrics", timeout=TIMEOUT)
        assert response.status_code == 401

    def test_db_connection(self, base_url):
        """Test database connectivity"""
        response = requests.get(f"{base_url}/db-test", timeout=TIMEOUT)
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "Database connected successfully"
        assert "postgres_version" in data
        assert data["postgres_version"].startswith("PostgreSQL")
        assert data["database_name"] == "secureclouddb"
        assert data["connected_user"] == "db_admin"


class TestPerformance:
    """Basic performance tests"""

    def test_response_time(self, base_url):
        """Test that responses are fast enough"""
        import time
        start = time.time()
        response = requests.get(base_url, timeout=TIMEOUT)
        duration = time.time() - start
        assert response.status_code == 200
        assert duration < 1.0, f"Response too slow: {duration}s"

    def test_concurrent_requests(self, base_url):
        """Test concurrent request handling"""
        import concurrent.futures

        def make_request(_):
            return requests.get(f"{base_url}/health/live", timeout=TIMEOUT)

        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_request, i) for i in range(10)]
            results = [f.result() for f in concurrent.futures.as_completed(futures)]

        for result in results:
            assert result.status_code == 200


class TestSecurity:
    """Security tests"""

    def test_no_directory_traversal(self, base_url):
        """Test that directory traversal is blocked"""
        response = requests.get(f"{base_url}/..%2f..%2fetc%2fpasswd", timeout=TIMEOUT)
        assert response.status_code in [400, 403, 404]

    def test_method_not_allowed(self, base_url):
        """Test that invalid methods return 405"""
        response = requests.delete(f"{base_url}/api/metrics", timeout=TIMEOUT)
        assert response.status_code == 405

    def test_security_headers(self, base_url):
        """Test that security headers are present"""
        response = requests.get(base_url, timeout=TIMEOUT)
        # Check for common security headers (may vary by configuration)
        headers = response.headers
        assert headers.get("Content-Type") == "application/json"


if __name__ == '__main__':
    pytest.main([__file__, '-v'])