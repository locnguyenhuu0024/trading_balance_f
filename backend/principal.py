"""Immutable user identity and owner scope used by private v2 services."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal


AuthMode = Literal["ordinary", "enrollment", "mfa_recovery"]


@dataclass(frozen=True, slots=True)
class OwnerScope:
    """The validated owner and connection attached to a private child row."""

    user_id: str
    connection_id: str

    def __post_init__(self) -> None:
        if not self.user_id or not self.connection_id:
            raise ValueError("owner and connection are required")


@dataclass(frozen=True, slots=True)
class Principal:
    """Server-validated session identity; never constructed from request fields."""

    user_id: str
    session_id: str
    auth_version: int
    mode: AuthMode
    created_at: float
    last_seen_at: float
    expires_at: float
    step_up_until: float | None = None

    def owner_scope(self, connection_id: str) -> OwnerScope:
        if self.mode != "ordinary":
            raise PermissionError("restricted sessions have no private owner scope")
        return OwnerScope(self.user_id, connection_id)

    def has_recent_step_up(self, now: float) -> bool:
        return (
            self.mode == "ordinary"
            and self.step_up_until is not None
            and self.step_up_until > now
            and self.step_up_until <= self.expires_at
        )
