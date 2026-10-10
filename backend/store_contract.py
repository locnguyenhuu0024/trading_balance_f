"""Shared identity-store protocol and safe storage exceptions."""

from __future__ import annotations

from contextlib import AbstractContextManager
from typing import Any, Protocol, Sequence


class IdentityStoreConflict(Exception):
    """A uniqueness or relational constraint rejected an identity write."""


class IdentityStoreUnavailable(Exception):
    """The identity database or its required driver is unavailable."""


class IdentityCursor(Protocol):
    rowcount: int

    def fetchone(self) -> Any: ...

    def fetchall(self) -> list[Any]: ...


class IdentityConnection(Protocol):
    def execute(self, sql: str, parameters: Sequence[Any] = ()) -> IdentityCursor: ...


class IdentityStore(Protocol):
    """Transactional DB-API surface; callers use only portable SQL in this contract."""

    dialect: str

    def initialize(self) -> None: ...

    def connection(self) -> AbstractContextManager[IdentityConnection]: ...

    def transaction(self) -> AbstractContextManager[IdentityConnection]: ...
