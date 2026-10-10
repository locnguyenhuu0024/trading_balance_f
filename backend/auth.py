"""Invitation-only multi-user authentication and offline invite administration."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import os
import secrets
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Callable

from .principal import Principal
from .security import (
    CryptoInvalidCiphertext,
    CryptoUnavailable,
    SeedCipher,
    current_time,
    generate_totp_secret,
    hash_password,
    matching_totp_counter,
    new_bearer_token,
    token_digest,
    verify_password,
)
from .store_contract import IdentityStore, IdentityStoreConflict, IdentityStoreUnavailable


LOGIN_WINDOW_SECONDS = 900
LOGIN_FAILURE_LIMIT = 5
SESSION_ABSOLUTE_SECONDS = 12 * 60 * 60
SESSION_IDLE_SECONDS = 30 * 60
SESSION_SEEN_DEBOUNCE_SECONDS = 60
ENROLLMENT_SESSION_SECONDS = 15 * 60
ENROLLMENT_CHALLENGE_SECONDS = 15 * 60
STEP_UP_SECONDS = 5 * 60
RECOVERY_CODE_COUNT = 10


def _utc_timestamp(value: float) -> str:
    return datetime.fromtimestamp(value, tz=timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


class IdentityAuthError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


class AuthenticationBusy(Exception):
    """The finite per-process scrypt admission queue is full."""


class _ScryptAdmission:
    """Four workers with four queued requests; never creates an unbounded queue."""

    def __init__(self) -> None:
        self._executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="identity-scrypt")
        self._slots = threading.BoundedSemaphore(8)

    def run(self, function: Callable[..., Any], *args: Any) -> Any:
        if not self._slots.acquire(blocking=False):
            raise AuthenticationBusy
        try:
            future = self._executor.submit(function, *args)
        except Exception:
            self._slots.release()
            raise
        future.add_done_callback(lambda _: self._slots.release())
        return future.result()


_SCRYPT_ADMISSION = _ScryptAdmission()


@dataclass(frozen=True, slots=True)
class IssuedSession:
    token: str
    csrf_token: str
    user_id: str
    username: str
    session_id: str
    mode: str
    expires_at: float

    def safe_fields(self) -> dict[str, Any]:
        return {
            "userId": self.user_id,
            "username": self.username,
            "sessionId": self.session_id,
            "mode": self.mode,
            "expiresAt": _utc_timestamp(self.expires_at),
        }


class IdentityAuthService:
    """Owns v2 identity transitions; private trading authorization stays separate."""

    def __init__(
        self,
        store: IdentityStore,
        signing_key: bytes,
        seed_cipher: SeedCipher | None,
        *,
        clock: Callable[[], float] = current_time,
    ):
        if len(signing_key) != 32:
            raise ValueError("session signing key must be 32 bytes")
        self.store = store
        self.signing_key = bytes(signing_key)
        self.seed_cipher = seed_cipher
        self.clock = clock
        self._dummy_password_hash: str | None = None
        self._dummy_lock = threading.Lock()

    def _dummy_hash(self) -> str:
        if self._dummy_password_hash is None:
            with self._dummy_lock:
                if self._dummy_password_hash is None:
                    self._dummy_password_hash = _SCRYPT_ADMISSION.run(
                        hash_password, secrets.token_urlsafe(32)
                    )
        return self._dummy_password_hash

    def _verify_password(self, password: Any, encoded: str | None) -> bool:
        candidate = password if isinstance(password, str) and len(password) <= 1024 else ""
        reference = encoded if encoded is not None else self._dummy_hash()
        return bool(_SCRYPT_ADMISSION.run(verify_password, candidate, reference)) and encoded is not None

    @staticmethod
    def normalize_username(value: Any) -> tuple[str, str] | None:
        if not isinstance(value, str):
            return None
        normalized = value.strip().lower()
        if (
            not normalized
            or len(normalized) < 3
            or len(normalized) > 64
            or not normalized.isascii()
            or any(ord(char) < 33 or ord(char) > 126 for char in normalized)
        ):
            return None
        return value.strip(), normalized

    def _bucket_keys(self, source: str, username: str) -> tuple[str, str]:
        return (
            token_digest("auth-source:" + source, self.signing_key),
            token_digest("auth-username:" + username, self.signing_key),
        )

    def _reserve_attempts(self, buckets: tuple[str, str], now: float) -> None:
        """Atomically reserve failure budget before password or OTP work."""
        try:
            with self.store.transaction() as connection:
                for bucket in buckets:
                    row = connection.execute(
                        "INSERT INTO multiuser_login_attempts(bucket_key, window_started, failures, reserved) "
                        "VALUES (?, ?, 0, 1) ON CONFLICT(bucket_key) DO UPDATE SET "
                        "window_started=CASE WHEN excluded.window_started - multiuser_login_attempts.window_started >= ? "
                        "THEN excluded.window_started ELSE multiuser_login_attempts.window_started END, "
                        "failures=CASE WHEN excluded.window_started - multiuser_login_attempts.window_started >= ? "
                        "THEN 0 ELSE multiuser_login_attempts.failures END, "
                        "reserved=CASE WHEN excluded.window_started - multiuser_login_attempts.window_started >= ? "
                        "THEN 1 ELSE multiuser_login_attempts.reserved + 1 END "
                        "RETURNING failures, reserved",
                        (bucket, now, LOGIN_WINDOW_SECONDS, LOGIN_WINDOW_SECONDS, LOGIN_WINDOW_SECONDS),
                    ).fetchone()
                    if int(row["failures"]) + int(row["reserved"]) > LOGIN_FAILURE_LIMIT:
                        raise IdentityAuthError(
                            429, "rate_limited", "Too many authentication attempts. Try again later."
                        )
        except IdentityStoreUnavailable:
            raise

    def _record_failures(self, buckets: tuple[str, str], now: float) -> None:
        with self.store.transaction() as connection:
            self._settle_failures(connection, buckets, now)

    @staticmethod
    def _settle_failures(connection: Any, buckets: tuple[str, str], now: float) -> None:
        for bucket in buckets:
            connection.execute(
                "INSERT INTO multiuser_login_attempts(bucket_key, window_started, failures, reserved) "
                "VALUES (?, ?, 1, 0) ON CONFLICT(bucket_key) DO UPDATE SET "
                "window_started=CASE WHEN excluded.window_started - multiuser_login_attempts.window_started >= ? "
                "THEN excluded.window_started ELSE multiuser_login_attempts.window_started END, "
                "failures=CASE WHEN excluded.window_started - multiuser_login_attempts.window_started >= ? "
                "THEN 1 ELSE multiuser_login_attempts.failures + 1 END, "
                "reserved=CASE WHEN excluded.window_started - multiuser_login_attempts.window_started >= ? "
                "THEN 0 WHEN multiuser_login_attempts.reserved > 0 "
                "THEN multiuser_login_attempts.reserved - 1 ELSE 0 END",
                (bucket, now, LOGIN_WINDOW_SECONDS, LOGIN_WINDOW_SECONDS, LOGIN_WINDOW_SECONDS),
            )

    def _release_attempts(self, buckets: tuple[str, str], connection: Any) -> None:
        for bucket in buckets:
            connection.execute(
                "UPDATE multiuser_login_attempts SET reserved=CASE WHEN reserved > 0 THEN reserved - 1 ELSE 0 END "
                "WHERE bucket_key=?",
                (bucket,),
            )

    def _clear_failures(self, buckets: tuple[str, str], connection: Any) -> None:
        self._release_attempts(buckets, connection)
        # Clear only settled failures. Other processes may still own reservations
        # against this shared username/user bucket and those must remain counted.
        connection.execute(
            "UPDATE multiuser_login_attempts SET failures=0 WHERE bucket_key=?",
            (buckets[1],),
        )

    def _transition_buckets(self, user_id: str, session_id: str) -> tuple[str, str]:
        return (
            token_digest("auth-session:" + session_id, self.signing_key),
            token_digest("auth-user:" + user_id, self.signing_key),
        )

    def _enrollment_start_buckets(self, user_id: str, session_id: str) -> tuple[str, str]:
        return (
            token_digest("enrollment-start-session:" + session_id, self.signing_key),
            token_digest("enrollment-start-user:" + user_id, self.signing_key),
        )

    def _select_user(self, connection: Any, user_id: str, fields: str) -> Any:
        suffix = " FOR UPDATE" if self.store.dialect == "postgresql" else ""
        return connection.execute(
            f"SELECT {fields} FROM users WHERE user_id=?{suffix}", (user_id,)
        ).fetchone()

    def _select_session(self, connection: Any, session_id: str) -> Any:
        suffix = " FOR UPDATE" if self.store.dialect == "postgresql" else ""
        return connection.execute(
            "SELECT user_id, auth_version, auth_mode, created_at, expires_at, last_seen_at, revoked_at, "
            "step_up_until FROM user_sessions WHERE session_id=?" + suffix,
            (session_id,),
        ).fetchone()

    def _require_persisted_principal(
        self,
        connection: Any,
        principal: Principal,
        now: float,
        expected_status: str,
    ) -> tuple[Any, Any]:
        user = self._select_user(connection, principal.user_id, "status, auth_version")
        session = self._select_session(connection, principal.session_id)
        if (
            user is None
            or session is None
            or user["status"] != expected_status
            or int(user["auth_version"]) != principal.auth_version
            or session["user_id"] != principal.user_id
            or int(session["auth_version"]) != principal.auth_version
            or session["auth_mode"] != principal.mode
            or session["revoked_at"] is not None
            or float(session["expires_at"]) <= now
            or now - float(session["last_seen_at"]) >= SESSION_IDLE_SECONDS
        ):
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        return user, session

    def _require_cipher(self) -> SeedCipher:
        if self.seed_cipher is None:
            raise CryptoUnavailable("the MFA seed cipher is not configured")
        return self.seed_cipher

    def _csrf_token_for_session(self, session_id: str) -> str:
        return token_digest("v2-cookie-csrf:" + session_id, self.signing_key)

    def _new_session(
        self,
        connection: Any,
        *,
        user_id: str,
        username: str,
        auth_version: int,
        mode: str,
        now: float,
        lifetime: float,
    ) -> IssuedSession:
        token = new_bearer_token()
        session_id = uuid.uuid4().hex
        csrf_token = self._csrf_token_for_session(session_id)
        expires_at = now + lifetime
        connection.execute(
            "INSERT INTO user_sessions(session_id, token_hash, user_id, auth_version, auth_mode, csrf_hash, "
            "created_at, expires_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                session_id,
                token_digest(token, self.signing_key),
                user_id,
                auth_version,
                mode,
                token_digest(csrf_token, self.signing_key),
                now,
                expires_at,
                now,
            ),
        )
        return IssuedSession(token, csrf_token, user_id, username, session_id, mode, expires_at)

    def create_invite(self) -> tuple[str, str]:
        """Create a 24-hour single-use invite; return its id and raw token once."""
        now = self.clock()
        invite_id = uuid.uuid4().hex
        token = new_bearer_token()
        self.store.initialize()
        with self.store.transaction() as connection:
            connection.execute(
                "INSERT INTO user_invites(invite_id, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?)",
                (invite_id, token_digest(token, self.signing_key), now, now + 24 * 60 * 60),
            )
        return invite_id, token

    def revoke_invite(self, invite_id: str) -> bool:
        now = self.clock()
        with self.store.transaction() as connection:
            changed = connection.execute(
                "UPDATE user_invites SET revoked_at=? WHERE invite_id=? AND consumed_at IS NULL AND revoked_at IS NULL",
                (now, invite_id),
            ).rowcount
        return changed == 1

    def activate_invite(
        self,
        invite_token: Any,
        username: Any,
        password: Any,
        source: str,
    ) -> IssuedSession:
        now = self.clock()
        normalized = self.normalize_username(username)
        source_name = source if isinstance(source, str) and source else "unknown"
        username_key = normalized[1] if normalized else "invalid"
        buckets = self._bucket_keys(source_name, username_key)
        self._reserve_attempts(buckets, now)
        token = invite_token if isinstance(invite_token, str) and len(invite_token) <= 256 else ""
        digest = token_digest(token, self.signing_key) if token else ""
        with self.store.connection() as connection:
            invite = connection.execute(
                "SELECT invite_id, expires_at, revoked_at, consumed_at FROM user_invites WHERE token_hash=?",
                (digest,),
            ).fetchone() if digest else None
        if (
            invite is None
            or float(invite["expires_at"]) <= now
            or invite["revoked_at"] is not None
            or invite["consumed_at"] is not None
            or normalized is None
            or not isinstance(password, str)
            or len(password) < 16
            or len(password) > 1024
        ):
            self._record_failures(buckets, now)
            raise IdentityAuthError(400, "invite_invalid", "The invitation or activation details are invalid.")
        try:
            password_hash = _SCRYPT_ADMISSION.run(hash_password, password)
        except AuthenticationBusy:
            with self.store.transaction() as connection:
                self._release_attempts(buckets, connection)
            raise
        user_id = uuid.uuid4().hex
        username_text, username_normalized = normalized
        try:
            with self.store.transaction() as connection:
                connection.execute(
                    "INSERT INTO users(user_id, username, username_normalized, password_hash, status, auth_version, created_at) "
                    "VALUES (?, ?, ?, ?, 'PENDING_ENROLLMENT', 1, ?)",
                    (user_id, username_text, username_normalized, password_hash, now),
                )
                changed = connection.execute(
                    "UPDATE user_invites SET consumed_at=?, activated_user_id=? WHERE invite_id=? "
                    "AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at>?",
                    (now, user_id, invite["invite_id"], now),
                ).rowcount
                if changed != 1:
                    raise IdentityAuthError(400, "invite_invalid", "The invitation or activation details are invalid.")
                session = self._new_session(
                    connection,
                    user_id=user_id,
                    username=username_text,
                    auth_version=1,
                    mode="enrollment",
                    now=now,
                    lifetime=ENROLLMENT_SESSION_SECONDS,
                )
        except IdentityStoreConflict:
            self._record_failures(buckets, now)
            raise IdentityAuthError(409, "invite_invalid", "The invitation or activation details are invalid.") from None
        except IdentityAuthError:
            self._record_failures(buckets, now)
            raise
        with self.store.transaction() as connection:
            self._clear_failures(buckets, connection)
        return session

    def login(
        self,
        username: Any,
        password: Any,
        *,
        totp: Any = None,
        recovery_code: Any = None,
        source: str,
    ) -> IssuedSession:
        now = self.clock()
        normalized = self.normalize_username(username)
        username_key = normalized[1] if normalized else "invalid"
        buckets = self._bucket_keys(source if source else "unknown", username_key)
        self._reserve_attempts(buckets, now)
        if normalized is None:
            user = None
        else:
            with self.store.connection() as connection:
                user = connection.execute(
                    "SELECT user_id, username, password_hash, status, auth_version "
                    "FROM users WHERE username_normalized=?",
                    (username_key,),
                ).fetchone()
        encoded = None if user is None else str(user["password_hash"])
        try:
            password_ok = self._verify_password(password, encoded)
        except AuthenticationBusy:
            with self.store.transaction() as connection:
                self._release_attempts(buckets, connection)
            raise
        if not password_ok or user is None:
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
        try:
            if recovery_code is not None:
                if totp not in (None, ""):
                    self._record_failures(buckets, now)
                    raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
                return self._login_recovery(user, recovery_code, buckets, now)
            return self._login_totp(user, totp, buckets, now)
        except IdentityAuthError as error:
            if error.status >= 500:
                with self.store.transaction() as connection:
                    self._release_attempts(buckets, connection)
            raise

    def _login_totp(
        self, user: Any, code: Any, buckets: tuple[str, str], now: float
    ) -> IssuedSession:
        session: IssuedSession | None = None
        if user["status"] != "ACTIVE":
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
        with self.store.connection() as connection:
            mfa = connection.execute(
                "SELECT key_id, nonce, ciphertext, last_totp_counter FROM user_mfa WHERE user_id=?",
                (user["user_id"],),
            ).fetchone()
        if mfa is None:
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
        try:
            secret = self._require_cipher().decrypt(
                user["user_id"], mfa["key_id"], bytes(mfa["nonce"]), bytes(mfa["ciphertext"])
            )
        except (CryptoInvalidCiphertext, CryptoUnavailable):
            raise IdentityAuthError(503, "identity_crypto_unavailable", "Authentication is temporarily unavailable.") from None
        counter = (
            matching_totp_counter(secret, code, now, int(mfa["last_totp_counter"]))
            if isinstance(code, str)
            else None
        )
        if counter is None:
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
        try:
            with self.store.transaction() as connection:
                current = connection.execute(
                    "SELECT username, status, auth_version FROM users WHERE user_id=?" +
                    (" FOR UPDATE" if self.store.dialect == "postgresql" else ""),
                    (user["user_id"],),
                ).fetchone()
                if (
                    current is None
                    or current["status"] != "ACTIVE"
                    or int(current["auth_version"]) != int(user["auth_version"])
                ):
                    raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
                changed = connection.execute(
                    "UPDATE user_mfa SET last_totp_counter=?, updated_at=? WHERE user_id=? AND last_totp_counter<?",
                    (counter, now, user["user_id"], counter),
                ).rowcount
                if changed != 1:
                    raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
                session = self._new_session(
                    connection,
                    user_id=user["user_id"],
                    username=current["username"],
                    auth_version=int(current["auth_version"]),
                    mode="ordinary",
                    now=now,
                    lifetime=SESSION_ABSOLUTE_SECONDS,
                )
        except IdentityAuthError:
            self._record_failures(buckets, now)
            raise
        with self.store.transaction() as connection:
            self._clear_failures(buckets, connection)
        if session is None:
            raise IdentityAuthError(503, "identity_unavailable", "Authentication is temporarily unavailable.")
        return session

    @staticmethod
    def _split_recovery_code(value: Any) -> tuple[str, str] | None:
        if not isinstance(value, str) or len(value) > 128 or "." not in value:
            return None
        code_id, secret = value.split(".", 1)
        if (
            len(code_id) != 12
            or any(char not in "0123456789abcdef" for char in code_id)
            or len(secret) < 20
            or len(secret) > 64
        ):
            return None
        return code_id, secret

    def _login_recovery(
        self, user: Any, code: Any, buckets: tuple[str, str], now: float
    ) -> IssuedSession:
        parsed = self._split_recovery_code(code)
        if parsed is None or user["status"] not in ("ACTIVE", "MFA_RECOVERY"):
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
        code_id, secret = parsed
        with self.store.connection() as connection:
            stored = connection.execute(
                "SELECT code_salt, code_hash, consumed_at FROM user_recovery_codes WHERE user_id=? AND code_id=?",
                (user["user_id"], code_id),
            ).fetchone()
        salt = bytes(stored["code_salt"]) if stored is not None else b"\x00" * 16
        expected = bytes(stored["code_hash"]) if stored is not None else b"\x00" * 32
        actual = hashlib.sha256(salt + secret.encode("utf-8")).digest()
        matched = hmac.compare_digest(actual, expected) and stored is not None and stored["consumed_at"] is None
        if not matched:
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
        session: IssuedSession | None = None
        try:
            with self.store.transaction() as connection:
                current = connection.execute(
                    "SELECT username, status, auth_version FROM users WHERE user_id=?" +
                    (" FOR UPDATE" if self.store.dialect == "postgresql" else ""),
                    (user["user_id"],),
                ).fetchone()
                if (
                    current is None
                    or current["status"] not in ("ACTIVE", "MFA_RECOVERY")
                    or int(current["auth_version"]) != int(user["auth_version"])
                ):
                    raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
                changed = connection.execute(
                    "UPDATE user_recovery_codes SET consumed_at=? WHERE user_id=? AND code_id=? AND consumed_at IS NULL",
                    (now, user["user_id"], code_id),
                ).rowcount
                if changed != 1:
                    raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
                changed = connection.execute(
                    "UPDATE users SET status='MFA_RECOVERY', auth_version=auth_version+1 "
                    "WHERE user_id=? AND auth_version=? AND status IN ('ACTIVE', 'MFA_RECOVERY')",
                    (user["user_id"], user["auth_version"]),
                ).rowcount
                if changed != 1:
                    raise IdentityAuthError(401, "invalid_credentials", "The username or authentication code is invalid.")
                auth_version = int(user["auth_version"]) + 1
                connection.execute(
                    "UPDATE user_sessions SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
                    (now, user["user_id"]),
                )
                session = self._new_session(
                    connection,
                    user_id=user["user_id"],
                    username=current["username"],
                    auth_version=auth_version,
                    mode="mfa_recovery",
                    now=now,
                    lifetime=ENROLLMENT_SESSION_SECONDS,
                )
        except IdentityAuthError:
            self._record_failures(buckets, now)
            raise
        with self.store.transaction() as connection:
            self._clear_failures(buckets, connection)
        if session is None:
            raise IdentityAuthError(503, "identity_unavailable", "Authentication is temporarily unavailable.")
        return session

    @staticmethod
    def _recovery_record() -> tuple[str, bytes, bytes, str]:
        code_id = secrets.token_hex(6)
        secret = secrets.token_urlsafe(24)
        salt = secrets.token_bytes(16)
        digest = hashlib.sha256(salt + secret.encode("utf-8")).digest()
        return code_id, salt, digest, f"{code_id}.{secret}"

    def start_enrollment(self, principal: Principal) -> dict[str, Any]:
        if principal.mode not in ("enrollment", "mfa_recovery"):
            raise IdentityAuthError(403, "recovery_required", "This session cannot enroll multi-factor authentication.")
        now = self.clock()
        buckets = self._enrollment_start_buckets(principal.user_id, principal.session_id)
        self._reserve_attempts(buckets, now)
        try:
            cipher = self._require_cipher()
            seed = generate_totp_secret()
            nonce, ciphertext = cipher.encrypt(principal.user_id, seed)
            enrollment_id = uuid.uuid4().hex
            recovery_records = [self._recovery_record() for _ in range(RECOVERY_CODE_COUNT)]
            with self.store.transaction() as connection:
                expected_status = "PENDING_ENROLLMENT" if principal.mode == "enrollment" else "MFA_RECOVERY"
                self._require_persisted_principal(connection, principal, now, expected_status)
                connection.execute(
                    "DELETE FROM user_mfa_enrollments WHERE user_id=? AND completed_at IS NULL",
                    (principal.user_id,),
                )
                connection.execute(
                    "INSERT INTO user_mfa_enrollments(enrollment_id, user_id, session_id, key_id, nonce, ciphertext, "
                    "created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (
                        enrollment_id,
                        principal.user_id,
                        principal.session_id,
                        cipher.key_id,
                        nonce,
                        ciphertext,
                        now,
                        now + ENROLLMENT_CHALLENGE_SECONDS,
                    ),
                )
                for code_id, salt, code_hash, _ in recovery_records:
                    connection.execute(
                        "INSERT INTO pending_recovery_codes(enrollment_id, code_id, code_salt, code_hash, created_at) "
                        "VALUES (?, ?, ?, ?, ?)",
                        (enrollment_id, code_id, salt, code_hash, now),
                    )
            # Repeated enrollment starts are counted after the user/session lock is released.
            self._record_failures(buckets, now)
        except Exception:
            with self.store.transaction() as connection:
                self._release_attempts(buckets, connection)
            raise
        return {
            "enrollmentId": enrollment_id,
            "totpSecret": seed,
            "recoveryCodes": [item[3] for item in recovery_records],
            "expiresAt": _utc_timestamp(now + ENROLLMENT_CHALLENGE_SECONDS),
        }

    def complete_enrollment(
        self,
        principal: Principal,
        code: Any,
        recovery_codes_saved: Any,
    ) -> dict[str, Any]:
        if principal.mode not in ("enrollment", "mfa_recovery"):
            raise IdentityAuthError(403, "recovery_required", "This session cannot complete multi-factor enrollment.")
        now = self.clock()
        buckets = self._transition_buckets(principal.user_id, principal.session_id)
        self._reserve_attempts(buckets, now)
        if recovery_codes_saved is not True:
            self._record_failures(buckets, now)
            raise IdentityAuthError(400, "recovery_ack_required", "Confirm that you saved the recovery codes.")
        with self.store.connection() as connection:
            enrollment = connection.execute(
                "SELECT enrollment_id, key_id, nonce, ciphertext, expires_at FROM user_mfa_enrollments "
                "WHERE user_id=? AND session_id=? AND completed_at IS NULL ORDER BY created_at DESC LIMIT 1",
                (principal.user_id, principal.session_id),
            ).fetchone()
        if enrollment is None or float(enrollment["expires_at"]) <= now:
            with self.store.transaction() as connection:
                self._release_attempts(buckets, connection)
            raise IdentityAuthError(400, "enrollment_expired", "Start a new multi-factor enrollment.")
        try:
            secret = self._require_cipher().decrypt(
                principal.user_id,
                enrollment["key_id"],
                bytes(enrollment["nonce"]),
                bytes(enrollment["ciphertext"]),
            )
        except (CryptoInvalidCiphertext, CryptoUnavailable):
            with self.store.transaction() as connection:
                self._release_attempts(buckets, connection)
            raise IdentityAuthError(503, "identity_crypto_unavailable", "Authentication is temporarily unavailable.") from None
        counter = matching_totp_counter(secret, code, now, -1) if isinstance(code, str) else None
        if counter is None:
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "invalid_totp", "The verification code is invalid.")
        with self.store.transaction() as connection:
            expected_status = "PENDING_ENROLLMENT" if principal.mode == "enrollment" else "MFA_RECOVERY"
            self._require_persisted_principal(connection, principal, now, expected_status)
            changed = connection.execute(
                "UPDATE user_mfa_enrollments SET completed_at=? WHERE enrollment_id=? AND user_id=? "
                "AND session_id=? AND completed_at IS NULL AND expires_at>?",
                (now, enrollment["enrollment_id"], principal.user_id, principal.session_id, now),
            ).rowcount
            if changed != 1:
                raise IdentityAuthError(409, "enrollment_replayed", "The enrollment challenge was already used.")
            connection.execute(
                "INSERT INTO user_mfa(user_id, key_id, nonce, ciphertext, last_totp_counter, updated_at) "
                "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(user_id) DO UPDATE SET "
                "key_id=excluded.key_id, nonce=excluded.nonce, ciphertext=excluded.ciphertext, "
                "last_totp_counter=excluded.last_totp_counter, updated_at=excluded.updated_at",
                (
                    principal.user_id,
                    enrollment["key_id"],
                    enrollment["nonce"],
                    enrollment["ciphertext"],
                    counter,
                    now,
                ),
            )
            connection.execute("DELETE FROM user_recovery_codes WHERE user_id=?", (principal.user_id,))
            connection.execute(
                "INSERT INTO user_recovery_codes(user_id, code_id, code_salt, code_hash, created_at) "
                "SELECT e.user_id, p.code_id, p.code_salt, p.code_hash, p.created_at "
                "FROM pending_recovery_codes p JOIN user_mfa_enrollments e ON e.enrollment_id=p.enrollment_id "
                "WHERE p.enrollment_id=?",
                (enrollment["enrollment_id"],),
            )
            changed = connection.execute(
                "UPDATE users SET status='ACTIVE' WHERE user_id=? AND auth_version=?",
                (principal.user_id, principal.auth_version),
            ).rowcount
            if changed != 1:
                raise IdentityAuthError(401, "authentication_required", "A valid enrollment session is required.")
            connection.execute(
                "DELETE FROM pending_recovery_codes WHERE enrollment_id=?",
                (enrollment["enrollment_id"],),
            )
            connection.execute(
                "UPDATE user_sessions SET revoked_at=? WHERE user_id=? AND auth_mode IN ('enrollment', 'mfa_recovery') "
                "AND revoked_at IS NULL",
                (now, principal.user_id),
            )
        with self.store.transaction() as connection:
            self._clear_failures(buckets, connection)
        return {
            "status": "activated" if principal.mode == "enrollment" else "recovery_complete",
            "requiresLogin": True,
        }

    def validate_session(self, token: str) -> Principal:
        if not token or len(token) > 256:
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        digest = token_digest(token, self.signing_key)
        now = self.clock()
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT s.session_id, s.user_id, s.auth_version, s.auth_mode, s.created_at, s.expires_at, "
                "s.last_seen_at, s.revoked_at, s.step_up_until, u.auth_version AS current_auth_version, "
                "u.status AS current_status FROM user_sessions s JOIN users u ON u.user_id=s.user_id "
                "WHERE s.token_hash=?",
                (digest,),
            ).fetchone()
        if row is None:
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")

        mode = str(row["auth_mode"])
        status_for_mode = {
            "ordinary": "ACTIVE",
            "enrollment": "PENDING_ENROLLMENT",
            "mfa_recovery": "MFA_RECOVERY",
        }
        expired = (
            row["revoked_at"] is not None
            or float(row["expires_at"]) <= now
            or now - float(row["last_seen_at"]) >= SESSION_IDLE_SECONDS
            or int(row["auth_version"]) != int(row["current_auth_version"])
            or row["current_status"] != status_for_mode.get(mode)
        )
        if expired:
            with self.store.transaction() as connection:
                connection.execute(
                    "UPDATE user_sessions SET revoked_at=COALESCE(revoked_at, ?) WHERE session_id=?",
                    (now, row["session_id"]),
                )
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        last_seen = float(row["last_seen_at"])
        if now - last_seen >= SESSION_SEEN_DEBOUNCE_SECONDS:
            still_valid = True
            with self.store.transaction() as connection:
                user = self._select_user(connection, str(row["user_id"]), "status, auth_version")
                session = self._select_session(connection, str(row["session_id"]))
                still_valid = bool(
                    user is not None
                    and session is not None
                    and user["status"] == status_for_mode.get(mode)
                    and int(user["auth_version"]) == int(row["auth_version"])
                    and session["user_id"] == row["user_id"]
                    and int(session["auth_version"]) == int(row["auth_version"])
                    and session["auth_mode"] == mode
                    and session["revoked_at"] is None
                    and float(session["expires_at"]) > now
                    and now - float(session["last_seen_at"]) < SESSION_IDLE_SECONDS
                )
                if not still_valid:
                    connection.execute(
                        "UPDATE user_sessions SET revoked_at=COALESCE(revoked_at, ?) WHERE session_id=?",
                        (now, row["session_id"]),
                    )
                else:
                    last_seen = float(session["last_seen_at"])
                    changed = connection.execute(
                        "UPDATE user_sessions SET last_seen_at=? WHERE session_id=? AND token_hash=? "
                        "AND auth_version=? AND revoked_at IS NULL AND last_seen_at<=? AND expires_at>?",
                        (
                            now,
                            row["session_id"],
                            digest,
                            row["auth_version"],
                            now - SESSION_SEEN_DEBOUNCE_SECONDS,
                            now,
                        ),
                    ).rowcount
                    if changed == 1:
                        last_seen = now
                    else:
                        # A competing refresh/revoke may win the debounce CAS.
                        latest = self._select_session(connection, str(row["session_id"]))
                        latest_user = self._select_user(connection, str(row["user_id"]), "status, auth_version")
                        still_valid = bool(
                            latest is not None
                            and latest_user is not None
                            and latest_user["status"] == status_for_mode.get(mode)
                            and int(latest_user["auth_version"]) == int(row["auth_version"])
                            and latest["user_id"] == row["user_id"]
                            and int(latest["auth_version"]) == int(row["auth_version"])
                            and latest["auth_mode"] == mode
                            and latest["revoked_at"] is None
                            and float(latest["expires_at"]) > now
                            and now - float(latest["last_seen_at"]) < SESSION_IDLE_SECONDS
                        )
                        if still_valid:
                            last_seen = float(latest["last_seen_at"])
                        else:
                            connection.execute(
                                "UPDATE user_sessions SET revoked_at=COALESCE(revoked_at, ?) WHERE session_id=?",
                                (now, row["session_id"]),
                            )
            if not still_valid:
                raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        if mode not in status_for_mode:
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        return Principal(
            user_id=str(row["user_id"]),
            session_id=str(row["session_id"]),
            auth_version=int(row["auth_version"]),
            mode=mode,  # type: ignore[arg-type]
            created_at=float(row["created_at"]),
            last_seen_at=last_seen,
            expires_at=float(row["expires_at"]),
            step_up_until=None if row["step_up_until"] is None else float(row["step_up_until"]),
        )

    def logout(self, principal: Principal) -> None:
        with self.store.transaction() as connection:
            connection.execute(
                "UPDATE user_sessions SET revoked_at=? WHERE session_id=? AND user_id=? AND revoked_at IS NULL",
                (self.clock(), principal.session_id, principal.user_id),
            )

    def validate_csrf(self, principal: Principal, token: Any) -> bool:
        if not isinstance(token, str) or not token or len(token) > 256:
            return False
        presented = token_digest(token, self.signing_key)
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT csrf_hash FROM user_sessions WHERE session_id=? AND user_id=? "
                "AND auth_version=? AND revoked_at IS NULL",
                (principal.session_id, principal.user_id, principal.auth_version),
            ).fetchone()
        return bool(
            row is not None
            and row["csrf_hash"] is not None
            and hmac.compare_digest(str(row["csrf_hash"]), presented)
        )

    def session_fields(self, principal: Principal) -> dict[str, Any]:
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT username FROM users WHERE user_id=? AND auth_version=?",
                (principal.user_id, principal.auth_version),
            ).fetchone()
        if row is None:
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        return {
            "userId": principal.user_id,
            "username": str(row["username"]),
            "sessionId": principal.session_id,
            "mode": principal.mode,
            "expiresAt": _utc_timestamp(principal.expires_at),
            "stepUpUntil": None if principal.step_up_until is None else _utc_timestamp(principal.step_up_until),
        }

    def csrf_token(self, principal: Principal) -> str:
        now = self.clock()
        expected_status = {
            "ordinary": "ACTIVE",
            "enrollment": "PENDING_ENROLLMENT",
            "mfa_recovery": "MFA_RECOVERY",
        }.get(principal.mode)
        if expected_status is None:
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT s.user_id, s.auth_version AS session_auth_version, s.auth_mode, s.csrf_hash, "
                "s.expires_at, s.last_seen_at, s.revoked_at, u.status AS current_status, "
                "u.auth_version AS current_auth_version FROM user_sessions s JOIN users u ON u.user_id=s.user_id "
                "WHERE s.session_id=? AND s.user_id=?",
                (principal.session_id, principal.user_id),
            ).fetchone()
        if (
            row is None
            or row["current_status"] != expected_status
            or int(row["current_auth_version"]) != principal.auth_version
            or row["user_id"] != principal.user_id
            or int(row["session_auth_version"]) != principal.auth_version
            or row["auth_mode"] != principal.mode
            or row["revoked_at"] is not None
            or float(row["expires_at"]) <= now
            or now - float(row["last_seen_at"]) >= SESSION_IDLE_SECONDS
        ):
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        token = self._csrf_token_for_session(principal.session_id)
        expected_hash = token_digest(token, self.signing_key)
        if row["csrf_hash"] is None or not hmac.compare_digest(str(row["csrf_hash"]), expected_hash):
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        return token

    def step_up(self, principal: Principal, password: Any, code: Any) -> float:
        if principal.mode != "ordinary":
            raise IdentityAuthError(403, "step_up_denied", "This session cannot request step-up authentication.")
        now = self.clock()
        buckets = self._transition_buckets(principal.user_id, principal.session_id)
        self._reserve_attempts(buckets, now)
        with self.store.connection() as connection:
            row = connection.execute(
                "SELECT u.password_hash, u.auth_version, m.key_id, m.nonce, m.ciphertext, m.last_totp_counter "
                "FROM users u JOIN user_mfa m ON m.user_id=u.user_id WHERE u.user_id=? AND u.status='ACTIVE'",
                (principal.user_id,),
            ).fetchone()
        if row is None or int(row["auth_version"]) != principal.auth_version:
            with self.store.transaction() as connection:
                self._release_attempts(buckets, connection)
            raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        try:
            password_ok = self._verify_password(password, str(row["password_hash"]))
        except AuthenticationBusy:
            with self.store.transaction() as connection:
                self._release_attempts(buckets, connection)
            raise
        if not password_ok:
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "step_up_invalid", "The password or verification code is invalid.")
        try:
            secret = self._require_cipher().decrypt(
                principal.user_id, row["key_id"], bytes(row["nonce"]), bytes(row["ciphertext"])
            )
        except (CryptoInvalidCiphertext, CryptoUnavailable):
            with self.store.transaction() as connection:
                self._release_attempts(buckets, connection)
            raise IdentityAuthError(503, "identity_crypto_unavailable", "Authentication is temporarily unavailable.") from None
        counter = matching_totp_counter(secret, code, now, int(row["last_totp_counter"])) if isinstance(code, str) else None
        if counter is None:
            self._record_failures(buckets, now)
            raise IdentityAuthError(401, "step_up_invalid", "The password or verification code is invalid.")
        step_up_until = 0.0
        try:
            with self.store.transaction() as connection:
                user = self._select_user(connection, principal.user_id, "status, auth_version")
                session = self._select_session(connection, principal.session_id)
                if (
                    user is None
                    or session is None
                    or user["status"] != "ACTIVE"
                    or int(user["auth_version"]) != principal.auth_version
                    or session["user_id"] != principal.user_id
                    or int(session["auth_version"]) != principal.auth_version
                    or session["auth_mode"] != "ordinary"
                    or session["revoked_at"] is not None
                    or float(session["expires_at"]) <= now
                    or now - float(session["last_seen_at"]) >= SESSION_IDLE_SECONDS
                ):
                    raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
                changed = connection.execute(
                    "UPDATE user_mfa SET last_totp_counter=?, updated_at=? WHERE user_id=? AND last_totp_counter<?",
                    (counter, now, principal.user_id, counter),
                ).rowcount
                if changed != 1:
                    raise IdentityAuthError(401, "step_up_invalid", "The password or verification code is invalid.")
                step_up_until = min(now + STEP_UP_SECONDS, float(session["expires_at"]))
                changed = connection.execute(
                    "UPDATE user_sessions SET step_up_until=? WHERE session_id=? AND user_id=? AND auth_version=? "
                    "AND auth_mode='ordinary' AND revoked_at IS NULL AND expires_at>? AND last_seen_at>?",
                    (
                        step_up_until,
                        principal.session_id,
                        principal.user_id,
                        principal.auth_version,
                        now,
                        now - SESSION_IDLE_SECONDS,
                    ),
                ).rowcount
                if changed != 1:
                    raise IdentityAuthError(401, "authentication_required", "A valid session is required.")
        except IdentityAuthError as error:
            if error.code == "step_up_invalid":
                self._record_failures(buckets, now)
            else:
                with self.store.transaction() as connection:
                    self._release_attempts(buckets, connection)
            raise
        with self.store.transaction() as connection:
            self._clear_failures(buckets, connection)
        return step_up_until


def _runtime_store_and_service() -> IdentityAuthService:
    dsn = os.environ.get("MULTIUSER_DATABASE_URL", "")
    signing_text = os.environ.get("SESSION_SIGNING_KEY", "")
    if not dsn or len(signing_text) != 64 or any(char not in "0123456789abcdefABCDEF" for char in signing_text):
        raise SystemExit("MULTIUSER_DATABASE_URL and SESSION_SIGNING_KEY are required")
    from .postgres_store import PostgresIdentityStore

    store = PostgresIdentityStore(dsn)
    store.initialize()
    return IdentityAuthService(store, bytes.fromhex(signing_text), None)


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Offline multi-user invite administration")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("init-schema", help="initialize the additive multi-user identity schema")
    subparsers.add_parser("create-invite", help="create a 24-hour, single-use activation invite")
    revoke = subparsers.add_parser("revoke-invite", help="revoke an unused invite by its public id")
    revoke.add_argument("invite_id")
    arguments = parser.parse_args(argv)
    try:
        auth = _runtime_store_and_service()
        if arguments.command == "init-schema":
            print("multi-user identity schema initialized")
            return 0
        if arguments.command == "create-invite":
            invite_id, token = auth.create_invite()
            print(f"inviteId={invite_id}")
            print(f"inviteToken={token}")
            return 0
        if arguments.command == "revoke-invite":
            if len(arguments.invite_id) != 32 or any(char not in "0123456789abcdef" for char in arguments.invite_id):
                raise SystemExit("invite id is invalid")
            if not auth.revoke_invite(arguments.invite_id):
                raise SystemExit("unused invite was not found")
            print("invite revoked")
            return 0
    except IdentityStoreUnavailable:
        raise SystemExit("identity database or PostgreSQL driver is unavailable") from None
    return 2


if __name__ == "__main__":
    raise SystemExit(_main())
