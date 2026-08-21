"""
SecureCloud Platform - Configuration Management
Loads configuration from environment variables and Azure Key Vault
"""
import os
from functools import lru_cache
from typing import Optional
from pydantic_settings import BaseSettings
from pydantic import Field
from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient


class Settings(BaseSettings):
    """Application settings loaded from environment and Key Vault"""

    # Application
    app_name: str = "securecloud-platform"
    environment: str = Field(default="development", alias="ENVIRONMENT")
    debug: bool = Field(default=False, alias="DEBUG")
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")

    # Azure
    azure_tenant_id: Optional[str] = Field(default=None, alias="AZURE_TENANT_ID")
    azure_client_id: Optional[str] = Field(default=None, alias="AZURE_CLIENT_ID")
    azure_subscription_id: Optional[str] = Field(default=None, alias="AZURE_SUBSCRIPTION_ID")
    key_vault_name: Optional[str] = Field(default=None, alias="KEY_VAULT_NAME")
    key_vault_uri: Optional[str] = Field(default=None, alias="KEY_VAULT_URI")

    # Database (loaded from Key Vault at runtime)
    db_host: Optional[str] = None
    db_name: Optional[str] = None
    db_username: Optional[str] = None
    db_password: Optional[str] = None

    # API Key (loaded from Key Vault at runtime)
    api_key: Optional[str] = None

    # Monitoring
    app_insights_connection_string: Optional[str] = Field(default=None, alias="APPLICATIONINSIGHTS_CONNECTION_STRING")
    enable_monitoring: bool = Field(default=True, alias="ENABLE_MONITORING")

    # Server
    host: str = Field(default="0.0.0.0", alias="HOST")
    port: int = Field(default=5000, alias="PORT")
    workers: int = Field(default=4, alias="WORKERS")

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False
        extra = "ignore"


@lru_cache
def get_settings() -> Settings:
    """Get cached settings instance"""
    return Settings()


class KeyVaultClient:
    """Client for fetching secrets from Azure Key Vault"""

    def __init__(self, settings: Settings):
        self.settings = settings
        self._client: Optional[SecretClient] = None
        self._cache: dict = {}

    def _get_client(self) -> SecretClient:
        """Get or create Key Vault client"""
        if self._client is None:
            if self.settings.azure_client_id:
                credential = ManagedIdentityCredential(client_id=self.settings.azure_client_id)
            else:
                credential = DefaultAzureCredential()

            vault_url = self.settings.key_vault_uri or f"https://{self.settings.key_vault_name}.vault.azure.net"
            self._client = SecretClient(vault_url=vault_url, credential=credential)
        return self._client

    def get_secret(self, name: str) -> str:
        """Get secret from Key Vault with caching"""
        if name in self._cache:
            return self._cache[name]

        try:
            client = self._get_client()
            secret = client.get_secret(name)
            self._cache[name] = secret.value
            return secret.value
        except Exception as e:
            raise RuntimeError(f"Failed to fetch secret '{name}' from Key Vault: {e}")

    def load_database_config(self) -> dict:
        """Load all database configuration from Key Vault"""
        return {
            "host": self.get_secret("db-host"),
            "name": self.get_secret("db-name"),
            "username": self.get_secret("db-username"),
            "password": self.get_secret("db-password"),
        }

    def load_api_key(self) -> str:
        """Load API key from Key Vault"""
        return self.get_secret("api-key")


class Config:
    """Flask configuration class"""

    def __init__(self):
        self.settings = get_settings()
        self.kv_client = KeyVaultClient(self.settings)

    @property
    def SECRET_KEY(self) -> str:
        """Flask secret key"""
        return os.environ.get("SECRET_KEY", "dev-secret-change-in-production")

    @property
    def DEBUG(self) -> bool:
        return self.settings.debug

    @property
    def ENV(self) -> str:
        return self.settings.environment

    def get_db_config(self) -> dict:
        """Get database configuration"""
        if self.settings.environment == "development" and not self.settings.key_vault_name:
            return {
                "host": os.environ.get("DB_HOST", "localhost"),
                "name": os.environ.get("DB_NAME", "secureclouddb"),
                "username": os.environ.get("DB_USERNAME", "db_admin"),
                "password": os.environ.get("DB_PASSWORD", "dev-password"),
            }
        return self.kv_client.load_database_config()

    def get_api_key(self) -> str:
        """Get API key"""
        if self.settings.environment == "development" and not self.settings.key_vault_name:
            return os.environ.get("API_KEY", "test-api-key-12345")
        return self.kv_client.load_api_key()