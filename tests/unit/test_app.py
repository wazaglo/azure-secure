"""
SecureCloud Platform - Unit Tests
"""
import os
import sys
import json
from unittest.mock import patch, MagicMock, Mock
import pytest

# Add repo root to path so 'app' is importable as a package
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)

from app.config import Settings, KeyVaultClient, Config
from app.database import DatabaseManager
from app import create_app


class TestConfig:
    """Test configuration management"""

    def test_settings_defaults(self):
        """Test default settings"""
        settings = Settings()
        assert settings.app_name == "securecloud-platform"
        assert settings.environment == "development"
        assert settings.debug is False
        assert settings.log_level == "INFO"

    def test_settings_from_env(self):
        """Test settings loaded from environment"""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "staging",
            "DEBUG": "true",
            "LOG_LEVEL": "DEBUG"
        }):
            settings = Settings()
            assert settings.environment == "staging"
            assert settings.debug is True
            assert settings.log_level == "DEBUG"

    def test_config_get_db_config_dev(self):
        """Test database config in development without Key Vault"""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "development",
            "DB_HOST": "localhost",
            "DB_NAME": "testdb",
            "DB_USERNAME": "testuser",
            "DB_PASSWORD": "testpass"
        }):
            config = Config()
            db_config = config.get_db_config()
            assert db_config["host"] == "localhost"
            assert db_config["name"] == "testdb"
            assert db_config["username"] == "testuser"
            assert db_config["password"] == "testpass"

    def test_config_get_api_key_dev(self):
        """Test API key in development without Key Vault"""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "development",
            "API_KEY": "test-api-key"
        }):
            config = Config()
            api_key = config.get_api_key()
            assert api_key == "test-api-key"


class TestDatabaseManager:
    """Test database connection management"""

    @patch('app.database.psycopg2.pool.ThreadedConnectionPool')
    def test_initialize_pool(self, mock_pool):
        """Test connection pool initialization"""
        mock_pool.return_value = MagicMock()
        manager = DatabaseManager()
        manager.settings.get_db_config = MagicMock(return_value={
            "host": "localhost",
            "name": "testdb",
            "username": "testuser",
            "password": "testpass"
        })
        manager.initialize(min_conn=1, max_conn=5)
        assert manager._pool is not None
        mock_pool.assert_called_once()

    @patch('app.database.psycopg2.pool.ThreadedConnectionPool')
    def test_health_check_success(self, mock_pool):
        """Test successful health check"""
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_conn.cursor.return_value = mock_cur
        mock_pool.return_value.getconn.return_value = mock_conn

        manager = DatabaseManager()
        manager._pool = mock_pool.return_value
        result = manager.health_check()
        assert result is True

    @patch('app.database.psycopg2.pool.ThreadedConnectionPool')
    def test_health_check_failure(self, mock_pool):
        """Test failed health check"""
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_cur.execute.side_effect = Exception("Connection failed")
        mock_conn.cursor.return_value = mock_cur
        mock_pool.return_value.getconn.return_value = mock_conn

        manager = DatabaseManager()
        manager._pool = mock_pool.return_value
        result = manager.health_check()
        assert result is False


class TestFlaskApp:
    """Test Flask application"""

    @pytest.fixture
    def app(self):
        """Create test Flask app"""
        with patch.dict(os.environ, {
            "ENVIRONMENT": "testing",
            "DEBUG": "true",
            "DB_HOST": "localhost",
            "DB_NAME": "testdb",
            "DB_USERNAME": "testuser",
            "DB_PASSWORD": "testpass",
            "API_KEY": "test-api-key"
        }):
            app = create_app()
            app.config['TESTING'] = True
            return app

    @pytest.fixture
    def client(self, app):
        """Create test client"""
        return app.test_client()

    @patch('app.routes.db_manager.health_check')
    def test_home_endpoint(self, mock_health, client):
        """Test home endpoint"""
        response = client.get('/')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['message'] == 'SecureCloud Platform API'
        assert data['version'] == '1.0.0'

    @patch('app.routes.db_manager.health_check')
    @patch('app.config.Config.get_db_config')
    def test_health_endpoint_healthy(self, mock_db_config, mock_health, client):
        """Test health endpoint when healthy"""
        mock_health.return_value = True
        mock_db_config.return_value = {
            "host": "localhost",
            "name": "testdb",
            "username": "testuser",
            "password": "testpass"
        }

        response = client.get('/health')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'healthy'
        assert data['checks']['database']['status'] == 'connected'
        assert data['checks']['key_vault']['status'] == 'connected'

    @patch('app.routes.db_manager.health_check')
    def test_health_endpoint_unhealthy(self, mock_health, client):
        """Test health endpoint when unhealthy"""
        mock_health.return_value = False

        response = client.get('/health')
        assert response.status_code == 503
        data = json.loads(response.data)
        assert data['status'] == 'unhealthy'
        assert data['checks']['database']['status'] == 'failed'

    def test_liveness_endpoint(self, client):
        """Test liveness probe"""
        response = client.get('/health/live')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'alive'

    @patch('app.routes.db_manager.health_check')
    def test_readiness_endpoint(self, mock_health, client):
        """Test readiness probe"""
        mock_health.return_value = True
        response = client.get('/health/ready')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['status'] == 'ready'

    @patch('app.routes.db_manager.health_check')
    def test_readiness_endpoint_not_ready(self, mock_health, client):
        """Test readiness probe when not ready"""
        mock_health.return_value = False
        response = client.get('/health/ready')
        assert response.status_code == 503

    def test_api_docs_endpoint(self, client):
        """Test API documentation endpoint"""
        response = client.get('/api')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'endpoints' in data
        assert len(data['endpoints']) == 6

    @patch('app.config.Config.get_api_key')
    def test_metrics_endpoint_valid_key(self, mock_api_key, client):
        """Test metrics endpoint with valid API key"""
        mock_api_key.return_value = "test-api-key"

        response = client.get('/api/metrics', headers={'X-API-Key': 'test-api-key'})
        assert response.status_code == 200
        data = json.loads(response.data)
        assert 'application' in data

    @patch('app.config.Config.get_api_key')
    def test_metrics_endpoint_invalid_key(self, mock_api_key, client):
        """Test metrics endpoint with invalid API key"""
        mock_api_key.return_value = "test-api-key"

        response = client.get('/api/metrics', headers={'X-API-Key': 'wrong-key'})
        assert response.status_code == 401
        data = json.loads(response.data)
        assert data['error'] == 'Invalid or missing API key'

    @patch('app.config.Config.get_api_key')
    def test_metrics_endpoint_missing_key(self, mock_api_key, client):
        """Test metrics endpoint without API key"""
        mock_api_key.return_value = "test-api-key"

        response = client.get('/api/metrics')
        assert response.status_code == 401
        data = json.loads(response.data)
        assert data['error'] == 'Invalid or missing API key'

    @patch('app.routes.db_manager.get_cursor')
    def test_db_test_endpoint(self, mock_cursor, client):
        """Test database test endpoint"""
        mock_cur = MagicMock()
        mock_cur.fetchone.return_value = {
            'postgres_version': 'PostgreSQL 16.0',
            'server_time': '2024-01-01 12:00:00',
            'database_name': 'secureclouddb',
            'connected_user': 'dbadmin',
            'server_ip': '10.0.4.4',
            'server_port': 5432
        }
        mock_cursor.return_value.__enter__.return_value = mock_cur

        response = client.get('/db-test')
        assert response.status_code == 200
        data = json.loads(response.data)
        assert data['message'] == 'Database connected successfully'
        assert 'postgres_version' in data


class TestKeyVaultClient:
    """Test Key Vault client"""

    @patch('app.config.DefaultAzureCredential')
    @patch('app.config.SecretClient')
    def test_get_secret(self, mock_secret_client, mock_credential):
        """Test getting secret from Key Vault"""
        mock_client = MagicMock()
        mock_secret = MagicMock()
        mock_secret.value = "test-secret-value"
        mock_client.get_secret.return_value = mock_secret
        mock_secret_client.return_value = mock_client

        settings = Settings()
        settings.key_vault_name = "test-kv"
        settings.key_vault_uri = "https://test-kv.vault.azure.net"

        kv_client = KeyVaultClient(settings)
        value = kv_client.get_secret("test-secret")

        assert value == "test-secret-value"
        mock_client.get_secret.assert_called_once_with("test-secret")

    @patch('app.config.DefaultAzureCredential')
    @patch('app.config.SecretClient')
    def test_get_secret_cached(self, mock_secret_client, mock_credential):
        """Test secret caching"""
        mock_client = MagicMock()
        mock_secret = MagicMock()
        mock_secret.value = "test-secret-value"
        mock_client.get_secret.return_value = mock_secret
        mock_secret_client.return_value = mock_client

        settings = Settings()
        settings.key_vault_name = "test-kv"

        kv_client = KeyVaultClient(settings)
        value1 = kv_client.get_secret("test-secret")
        value2 = kv_client.get_secret("test-secret")

        assert value1 == value2 == "test-secret-value"
        # Should only call Key Vault once due to caching
        assert mock_client.get_secret.call_count == 1


if __name__ == '__main__':
    pytest.main([__file__, '-v'])