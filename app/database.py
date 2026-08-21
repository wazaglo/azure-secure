"""
SecureCloud Platform - Database Connection Management
"""
import psycopg2
import psycopg2.extras
import psycopg2.pool
from contextlib import contextmanager
from typing import Optional, Any, Dict
import structlog
from app.config import get_settings
from app.extensions import DB_CONNECTION_POOL

logger = structlog.get_logger()


class DatabaseManager:
    """Manages PostgreSQL connection pool"""

    def __init__(self):
        self.settings = get_settings()
        self._pool: Optional[psycopg2.pool.ThreadedConnectionPool] = None

    def _get_connection_params(self) -> Dict[str, Any]:
        """Get database connection parameters"""
        config = self.settings.get_db_config()
        return {
            "host": config["host"],
            "database": config["name"],
            "user": config["username"],
            "password": config["password"],
            "connect_timeout": 10,
            "application_name": "securecloud-platform",
        }

    def initialize(self, min_conn: int = 2, max_conn: int = 10) -> None:
        """Initialize connection pool"""
        if self._pool is None:
            try:
                params = self._get_connection_params()
                self._pool = psycopg2.pool.ThreadedConnectionPool(
                    min_conn, max_conn, **params
                )
                DB_CONNECTION_POOL.set(max_conn)
                logger.info("database_pool_initialized", min_conn=min_conn, max_conn=max_conn)
            except Exception as e:
                logger.error("database_pool_init_failed", error=str(e))
                raise

    def close(self) -> None:
        """Close all connections in pool"""
        if self._pool:
            self._pool.closeall()
            self._pool = None
            DB_CONNECTION_POOL.set(0)
            logger.info("database_pool_closed")

    @contextmanager
    def get_connection(self):
        """Get a connection from the pool"""
        if not self._pool:
            self.initialize()

        conn = self._pool.getconn()
        try:
            yield conn
        except Exception:
            conn.rollback()
            raise
        finally:
            self._pool.putconn(conn)

    @contextmanager
    def get_cursor(self, cursor_factory=None):
        """Get a cursor from the pool"""
        with self.get_connection() as conn:
            cursor = conn.cursor(cursor_factory=cursor_factory)
            try:
                yield cursor
                conn.commit()
            except Exception:
                conn.rollback()
                raise
            finally:
                cursor.close()

    def health_check(self) -> bool:
        """Check database connectivity"""
        try:
            with self.get_cursor() as cur:
                cur.execute("SELECT 1")
                return True
        except Exception as e:
            logger.error("database_health_check_failed", error=str(e))
            return False

    def execute_query(self, query: str, params: tuple = None) -> list:
        """Execute a SELECT query"""
        with self.get_cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, params)
            return cur.fetchall()

    def execute_one(self, query: str, params: tuple = None) -> Optional[dict]:
        """Execute a query and return one row"""
        with self.get_cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(query, params)
            return cur.fetchone()


# Global database manager instance
db_manager = DatabaseManager()