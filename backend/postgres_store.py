"""Lazy psycopg-backed implementation of the identity-store contract."""

from __future__ import annotations

import threading
from contextlib import contextmanager
from typing import Any, Iterator, Sequence

from .schema_multiuser import ensure_schema
from .store_contract import IdentityStoreConflict, IdentityStoreUnavailable


class _PostgresConnection:
    def __init__(self, connection: Any, driver: Any):
        self._connection = connection
        self._driver = driver

    def execute(self, sql: str, parameters: Sequence[Any] = ()) -> Any:
        try:
            return self._connection.execute(sql.replace("?", "%s"), tuple(parameters))
        except self._driver.IntegrityError:
            raise IdentityStoreConflict("identity constraint rejected the write") from None


class PostgresIdentityStore:
    """A connection-per-operation PostgreSQL store; psycopg loads only when used."""

    dialect = "postgresql"

    def __init__(self, dsn: str):
        if not isinstance(dsn, str) or not dsn.strip():
            raise ValueError("PostgreSQL DSN is required")
        self._dsn = dsn
        self._init_lock = threading.Lock()
        self._initialized = False

    def _connect(self) -> tuple[Any, Any]:
        try:
            import psycopg
            from psycopg.rows import dict_row
        except ImportError:
            raise IdentityStoreUnavailable("the PostgreSQL driver is unavailable") from None
        try:
            connection = psycopg.connect(self._dsn, row_factory=dict_row, autocommit=True)
        except (psycopg.OperationalError, psycopg.InterfaceError):
            raise IdentityStoreUnavailable("the identity database is unavailable") from None
        return connection, psycopg

    @contextmanager
    def connection(self) -> Iterator[_PostgresConnection]:
        connection, driver = self._connect()
        try:
            yield _PostgresConnection(connection, driver)
        except (driver.OperationalError, driver.InterfaceError):
            raise IdentityStoreUnavailable("the identity database is unavailable") from None
        finally:
            connection.close()

    @contextmanager
    def transaction(self) -> Iterator[_PostgresConnection]:
        connection, driver = self._connect()
        try:
            connection.execute("BEGIN")
            try:
                yield _PostgresConnection(connection, driver)
                connection.commit()
            except Exception:
                connection.rollback()
                raise
        except (driver.OperationalError, driver.InterfaceError):
            raise IdentityStoreUnavailable("the identity database is unavailable") from None
        finally:
            connection.close()

    def initialize(self) -> None:
        if self._initialized:
            return
        with self._init_lock:
            if self._initialized:
                return
            with self.transaction() as connection:
                ensure_schema(connection, self.dialect)
            self._initialized = True
