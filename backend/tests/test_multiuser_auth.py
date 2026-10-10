from __future__ import annotations

import base64
from concurrent.futures import ThreadPoolExecutor
import os
from threading import Event
import unittest
from unittest.mock import patch
from tempfile import TemporaryDirectory

from backend.auth import IdentityAuthError
from backend.security import (
    AesGCMSeedCipher,
    CryptoInvalidCiphertext,
    _totp_at,
    token_digest,
)
from backend.service import APIError, RuntimeSettings, TradeService
from backend.store import SQLiteIdentityStore
from backend.app import WSGIApplication


class FabricatedSeedCipher:
    """Test-only injected cipher; never used by production runtime code."""

    key_id = "fabricated-test-only"

    def encrypt(self, user_id: str, secret: str) -> tuple[bytes, bytes]:
        return b"synthetic-nonce", user_id.encode("utf-8") + b"\x00" + secret.encode("ascii")

    def decrypt(self, user_id: str, key_id: str, nonce: bytes, ciphertext: bytes) -> str:
        prefix = user_id.encode("utf-8") + b"\x00"
        if key_id != self.key_id or not ciphertext.startswith(prefix):
            raise CryptoInvalidCiphertext("fabricated test seed mismatch")
        return ciphertext[len(prefix):].decode("ascii")


class MultiuserAuthTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.now = 1_800_000_000.0
        self.signing_key = b"S" * 32
        self.settings = RuntimeSettings(
            okx_api_key="",
            okx_api_secret="",
            okx_api_passphrase="",
            admin_password_hash="",
            totp_secret="",
            session_signing_key=self.signing_key,
            allowed_web_origin="https://tradingbalancef.example",
            operation_db_path=f"{self.temp.name}/operations.sqlite3",
            multiuser_enabled=True,
        )
        self.identity_store = SQLiteIdentityStore(self.settings.operation_db_path)
        self.service = TradeService(
            self.settings,
            identity_store=self.identity_store,
            seed_cipher=FabricatedSeedCipher(),
            clock=lambda: self.now,
        )
        self.identity_store.initialize()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _activate_and_enroll(self, username: str = "User.One") -> dict[str, object]:
        password = "disposable test password 16+"
        invite_id, invite_token = self.service.identity_auth.create_invite()
        activation = self.service.identity_auth.activate_invite(
            invite_token, username, password, "198.51.100.10"
        )
        enrollment_principal = self.service.identity_auth.validate_session(activation.token)
        enrollment = self.service.identity_auth.start_enrollment(enrollment_principal)
        secret = str(enrollment["totpSecret"])
        code = _totp_at(secret, int(self.now // 30))
        self.service.identity_auth.complete_enrollment(enrollment_principal, code, True)
        recovery_code = str(enrollment["recoveryCodes"][0])
        self.now += 30
        login_code = _totp_at(secret, int(self.now // 30))
        ordinary = self.service.identity_auth.login(
            username, password, totp=login_code, source="198.51.100.10"
        )
        return {
            "invite_id": invite_id,
            "password": password,
            "secret": secret,
            "recovery_code": recovery_code,
            "ordinary": ordinary,
        }

    def test_v2_session_rejects_a_valid_legacy_session_token(self) -> None:
        legacy_token = "legacy-session-token-that-must-not-cross"
        self.service.store.initialize()
        with self.service.store.transaction() as connection:
            connection.execute(
                "INSERT INTO sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)",
                (token_digest(legacy_token, self.signing_key), 9_999_999_999, 1),
            )

        with self.assertRaises(APIError) as caught:
            self.service.dispatch(
                "GET",
                "/v2/session",
                {},
                {
                    "HTTP_AUTHORIZATION": f"Bearer {legacy_token}",
                    "HTTP_X_SESSION_TRANSPORT": "bearer",
                },
            )

        self.assertEqual(caught.exception.status, 401)
        self.assertEqual(caught.exception.code, "authentication_required")

    def test_activation_inserts_user_before_consuming_foreign_key_invite(self) -> None:
        invite_id, invite_token = self.service.identity_auth.create_invite()
        issued = self.service.identity_auth.activate_invite(
            invite_token, "Foreign.Key", "a sufficiently long test password", "198.51.100.11"
        )
        principal = self.service.identity_auth.validate_session(issued.token)
        self.assertEqual(principal.mode, "enrollment")
        with self.identity_store.connection() as connection:
            invite = connection.execute(
                "SELECT activated_user_id FROM user_invites WHERE invite_id=?", (invite_id,)
            ).fetchone()
            user = connection.execute(
                "SELECT status FROM users WHERE user_id=?", (principal.user_id,)
            ).fetchone()
        self.assertEqual(invite["activated_user_id"], principal.user_id)
        self.assertEqual(user["status"], "PENDING_ENROLLMENT")

    def test_two_users_have_independent_identity_and_mfa_state(self) -> None:
        first = self._activate_and_enroll("First.User")
        second = self._activate_and_enroll("Second.User")
        first_principal = self.service.identity_auth.validate_session(first["ordinary"].token)
        second_principal = self.service.identity_auth.validate_session(second["ordinary"].token)
        self.assertNotEqual(first_principal.user_id, second_principal.user_id)
        self.assertNotEqual(first_principal.session_id, second_principal.session_id)
        self.assertEqual(first_principal.mode, "ordinary")
        self.assertEqual(second_principal.mode, "ordinary")
        self.assertEqual(first_principal.owner_scope("connection-a").user_id, first_principal.user_id)

    def test_malformed_username_cannot_match_a_literal_invalid_account(self) -> None:
        user = self._activate_and_enroll("invalid")
        # Use a fresh time counter so a same-counter replay cannot make the
        # malformed request appear safely rejected.
        self.now += 30
        fresh_code = _totp_at(str(user["secret"]), int(self.now // 30))
        with self.assertRaises(IdentityAuthError) as caught:
            self.service.identity_auth.login(
                None,
                str(user["password"]),
                totp=fresh_code,
                source="198.51.100.16",
            )
        self.assertEqual(caught.exception.status, 401)
        # The malformed attempt must not consume the user's valid fresh code.
        issued = self.service.identity_auth.login(
            "invalid",
            str(user["password"]),
            totp=fresh_code,
            source="198.51.100.17",
        )
        self.assertEqual(issued.username, "invalid")

    def test_success_keeps_another_inflight_username_reservation(self) -> None:
        user = self._activate_and_enroll("Admission.User")
        auth = self.service.identity_auth
        user_bucket = auth._bucket_keys("source-a", "admission.user")[1]
        self.now += 30
        paused = Event()
        release = Event()
        verify = auth._verify_password

        def pause_one_failure(password: object, encoded: str | None) -> bool:
            if password == "concurrent wrong password":
                paused.set()
                if not release.wait(timeout=15):
                    raise AssertionError("timed out waiting to finish the concurrent login")
                return False
            return verify(password, encoded)

        auth._verify_password = pause_one_failure  # type: ignore[method-assign]
        with ThreadPoolExecutor(max_workers=2) as pool:
            pending = pool.submit(
                auth.login,
                "Admission.User",
                "concurrent wrong password",
                totp="unused",
                source="source-a",
            )
            try:
                self.assertTrue(paused.wait(timeout=5), "first login did not reserve before verification")
                auth.login(
                    "Admission.User",
                    str(user["password"]),
                    totp=_totp_at(str(user["secret"]), int(self.now // 30)),
                    source="source-b",
                )
                with self.identity_store.connection() as connection:
                    row = connection.execute(
                        "SELECT failures, reserved FROM multiuser_login_attempts WHERE bucket_key=?",
                        (user_bucket,),
                    ).fetchone()
                self.assertEqual((row["failures"], row["reserved"]), (0, 1))

                for index in range(4):
                    with self.assertRaises(IdentityAuthError) as caught:
                        auth.login(
                            "Admission.User",
                            str(user["password"]),
                            totp="invalid-code",
                            source=f"invalid-source-{index}",
                        )
                    self.assertEqual(caught.exception.status, 401)
                with self.assertRaises(IdentityAuthError) as limited:
                    auth.login(
                        "Admission.User",
                        str(user["password"]),
                        totp="invalid-code",
                        source="invalid-source-final",
                    )
                self.assertEqual(limited.exception.status, 429)
            finally:
                release.set()
            with self.assertRaises(IdentityAuthError) as failed:
                pending.result(timeout=15)
            self.assertEqual(failed.exception.status, 401)

    def test_replayed_totp_is_atomically_rejected(self) -> None:
        user = self._activate_and_enroll("Replay.User")
        self.now += 30
        shared_code = _totp_at(str(user["secret"]), int(self.now // 30))

        def attempt() -> str:
            try:
                session = self.service.identity_auth.login(
                    "Replay.User",
                    str(user["password"]),
                    totp=shared_code,
                    source="198.51.100.12",
                )
                return session.user_id
            except IdentityAuthError as error:
                return f"denied:{error.status}"

        with ThreadPoolExecutor(max_workers=2) as pool:
            outcomes = list(pool.map(lambda _: attempt(), range(2)))
        self.assertEqual(sum(not outcome.startswith("denied:") for outcome in outcomes), 1)
        self.assertEqual(outcomes.count("denied:401"), 1)

    def test_recovery_requires_password_then_revokes_sessions_and_reenrolls(self) -> None:
        user = self._activate_and_enroll("Recovery.User")
        ordinary = user["ordinary"]
        recovery_code = str(user["recovery_code"])
        with self.assertRaises(IdentityAuthError) as wrong_password:
            self.service.identity_auth.login(
                "Recovery.User",
                "incorrect password long enough",
                recovery_code=recovery_code,
                source="198.51.100.13",
            )
        self.assertEqual(wrong_password.exception.status, 401)

        recovery_session = self.service.identity_auth.login(
            "Recovery.User",
            str(user["password"]),
            recovery_code=recovery_code,
            source="198.51.100.13",
        )
        restricted = self.service.identity_auth.validate_session(recovery_session.token)
        self.assertEqual(restricted.mode, "mfa_recovery")
        with self.assertRaises(PermissionError):
            restricted.owner_scope("private-connection")
        with self.assertRaises(IdentityAuthError) as step_up_denied:
            self.service.identity_auth.step_up(restricted, str(user["password"]), "000000")
        self.assertEqual(step_up_denied.exception.status, 403)
        with self.assertRaises(IdentityAuthError) as old_session_revoked:
            self.service.identity_auth.validate_session(ordinary.token)
        self.assertEqual(old_session_revoked.exception.status, 401)

        for bearer in (ordinary.token, recovery_session.token):
            with self.assertRaises(APIError) as private_denied:
                self.service.dispatch(
                    "GET", "/v1/positions", {}, {"HTTP_AUTHORIZATION": f"Bearer {bearer}"}
                )
            self.assertEqual(private_denied.exception.status, 401)

        with self.assertRaises(IdentityAuthError) as replayed_recovery:
            self.service.identity_auth.login(
                "Recovery.User",
                str(user["password"]),
                recovery_code=recovery_code,
                source="198.51.100.13",
            )
        self.assertEqual(replayed_recovery.exception.status, 401)

        challenge = self.service.identity_auth.start_enrollment(restricted)
        enrollment_code = _totp_at(str(challenge["totpSecret"]), int(self.now // 30))
        self.service.identity_auth.complete_enrollment(restricted, enrollment_code, True)
        self.now += 30
        ordinary_again = self.service.identity_auth.login(
            "Recovery.User",
            str(user["password"]),
            totp=_totp_at(str(challenge["totpSecret"]), int(self.now // 30)),
            source="198.51.100.13",
        )
        self.assertEqual(self.service.identity_auth.validate_session(ordinary_again.token).mode, "ordinary")

    def test_legacy_private_ingress_is_disabled_when_multiuser_is_enabled(self) -> None:
        legacy_token = "old-v1-private-token"
        self.service.store.initialize()
        with self.service.store.transaction() as connection:
            connection.execute(
                "INSERT INTO sessions(token_hash, expires_at, created_at) VALUES (?, ?, ?)",
                (token_digest(legacy_token, self.signing_key), 9_999_999_999, 1),
            )
        with self.assertRaises(APIError) as caught:
            self.service.dispatch(
                "POST", "/v1/logout", {}, {"HTTP_AUTHORIZATION": f"Bearer {legacy_token}"}
            )
        self.assertEqual(caught.exception.status, 401)

    def test_native_activation_returns_bearer_without_cookie_or_origin(self) -> None:
        _, invite_token = self.service.identity_auth.create_invite()
        status, payload, headers = self.service.dispatch(
            "POST",
            "/v2/invites/activate",
            {
                "inviteToken": invite_token,
                "username": "Native.User",
                "password": "a sufficiently long native password",
            },
            {"HTTP_X_SESSION_TRANSPORT": "bearer", "REMOTE_ADDR": "198.51.100.14"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["mode"], "enrollment")
        self.assertTrue(payload["token"])
        self.assertFalse(any(name.lower() == "set-cookie" for name, _ in headers))
        session_status, session_payload, _ = self.service.dispatch(
            "GET",
            "/v2/session",
            {},
            {
                "HTTP_AUTHORIZATION": f"Bearer {payload['token']}",
                "HTTP_X_SESSION_TRANSPORT": "bearer",
            },
        )
        self.assertEqual(session_status, 200)
        self.assertEqual(session_payload["mode"], "enrollment")
        self.assertNotIn("token", session_payload)

    def test_web_activation_restore_keeps_csrf_for_enrollment(self) -> None:
        _, invite_token = self.service.identity_auth.create_invite()
        status, activation_payload, headers = self.service.dispatch(
            "POST",
            "/v2/invites/activate",
            {
                "inviteToken": invite_token,
                "username": "Browser.Activation",
                "password": "a sufficiently long browser password",
            },
            {"HTTP_ORIGIN": self.settings.allowed_web_origin},
        )
        self.assertEqual(status, 200)
        self.assertNotIn("token", activation_payload)
        self.assertEqual(activation_payload["mode"], "enrollment")
        self.assertTrue(activation_payload["csrfToken"])
        cookies = [value for name, value in headers if name.lower() == "set-cookie"]
        session_cookie = next(value.split(";", 1)[0] for value in cookies if "_session=" in value)
        csrf_cookie = next(value.split(";", 1)[0] for value in cookies if "_csrf=" in value)
        cookie_header = f"{session_cookie}; {csrf_cookie}"

        restore_status, restored, restore_headers = self.service.dispatch(
            "GET", "/v2/session", {}, {"HTTP_COOKIE": cookie_header}
        )
        self.assertEqual(restore_status, 200)
        self.assertEqual(restored["mode"], "enrollment")
        self.assertEqual(restored["csrfToken"], activation_payload["csrfToken"])
        self.assertEqual(
            next(
                value.split(";", 1)[0]
                for name, value in restore_headers
                if name.lower() == "set-cookie" and "_csrf=" in value
            ),
            csrf_cookie,
        )

        enrollment_status, challenge, _ = self.service.dispatch(
            "POST",
            "/v2/mfa/enrollment",
            {},
            {
                "HTTP_ORIGIN": self.settings.allowed_web_origin,
                "HTTP_COOKIE": cookie_header,
                "HTTP_X_CSRF_TOKEN": activation_payload["csrfToken"],
            },
        )
        self.assertEqual(enrollment_status, 200)
        self.assertTrue(challenge["totpSecret"])
        self.assertTrue(challenge["recoveryCodes"])

    def test_web_cookie_transport_omits_bearer_and_requires_csrf_for_writes(self) -> None:
        user = self._activate_and_enroll("Browser.User")
        self.now += 30
        code = _totp_at(str(user["secret"]), int(self.now // 30))
        status, payload, headers = self.service.dispatch(
            "POST",
            "/v2/login",
            {"username": "Browser.User", "password": user["password"], "totp": code},
            {"HTTP_ORIGIN": self.settings.allowed_web_origin},
        )
        self.assertEqual(status, 200)
        self.assertNotIn("token", payload)
        self.assertTrue(payload["csrfToken"])
        set_cookies = [value for name, value in headers if name.lower() == "set-cookie"]
        self.assertEqual(len(set_cookies), 2)
        self.assertTrue(any("HttpOnly" in value and "SameSite=Strict" in value for value in set_cookies))
        session_cookie = next(value.split(";", 1)[0] for value in set_cookies if "_session=" in value)
        csrf_cookie = next(value.split(";", 1)[0] for value in set_cookies if "_csrf=" in value)
        cookie_header = f"{session_cookie}; {csrf_cookie}"
        csrf_token = payload["csrfToken"]
        session_token = session_cookie.partition("=")[2]
        with self.identity_store.connection() as connection:
            csrf_hash_before = connection.execute(
                "SELECT csrf_hash FROM user_sessions WHERE token_hash=?",
                (token_digest(session_token, self.signing_key),),
            ).fetchone()["csrf_hash"]

        def restore_session(_: int) -> tuple[int, dict[str, object], list[tuple[str, str]]]:
            return self.service.dispatch("GET", "/v2/session", {}, {"HTTP_COOKIE": cookie_header})

        with patch.object(
            self.service.identity_auth.store,
            "transaction",
            side_effect=AssertionError("cookie session restore must remain read-only"),
        ):
            with ThreadPoolExecutor(max_workers=4) as executor:
                restores = list(executor.map(restore_session, range(4)))

        for get_status, session_payload, restore_headers in restores:
            self.assertEqual(get_status, 200)
            self.assertEqual(session_payload["csrfToken"], csrf_token)
            self.assertEqual(
                next(
                    value.split(";", 1)[0]
                    for name, value in restore_headers
                    if name.lower() == "set-cookie" and "_csrf=" in value
                ),
                csrf_cookie,
            )
        with self.identity_store.connection() as connection:
            csrf_hash_after = connection.execute(
                "SELECT csrf_hash FROM user_sessions WHERE token_hash=?",
                (token_digest(session_token, self.signing_key),),
            ).fetchone()["csrf_hash"]
        self.assertEqual(csrf_hash_after, csrf_hash_before)
        self.assertEqual(csrf_hash_after, token_digest(csrf_token, self.signing_key))

        with self.assertRaises(APIError) as missing_csrf:
            self.service.dispatch(
                "POST",
                "/v2/logout",
                {},
                {"HTTP_ORIGIN": self.settings.allowed_web_origin, "HTTP_COOKIE": cookie_header},
            )
        self.assertEqual(missing_csrf.exception.status, 403)
        with self.assertRaises(APIError) as forged_csrf:
            self.service.dispatch(
                "POST",
                "/v2/logout",
                {},
                {
                    "HTTP_ORIGIN": self.settings.allowed_web_origin,
                    "HTTP_COOKIE": cookie_header,
                    "HTTP_X_CSRF_TOKEN": "forged-csrf-token",
                },
            )
        self.assertEqual(forged_csrf.exception.status, 403)
        logout_status, _, logout_headers = self.service.dispatch(
            "POST",
            "/v2/logout",
            {},
            {
                "HTTP_ORIGIN": self.settings.allowed_web_origin,
                "HTTP_COOKIE": cookie_header,
                "HTTP_X_CSRF_TOKEN": csrf_token,
            },
        )
        self.assertEqual(logout_status, 200)
        self.assertEqual(len([1 for name, _ in logout_headers if name.lower() == "set-cookie"]), 2)

    def test_enrollment_guess_budget_is_database_backed(self) -> None:
        user = self._activate_and_enroll("Throttle.User")
        recovery = self.service.identity_auth.login(
            "Throttle.User",
            str(user["password"]),
            recovery_code=str(user["recovery_code"]),
            source="198.51.100.15",
        )
        principal = self.service.identity_auth.validate_session(recovery.token)
        self.service.identity_auth.start_enrollment(principal)
        for _ in range(5):
            with self.assertRaises(IdentityAuthError) as invalid:
                self.service.identity_auth.complete_enrollment(principal, "not-a-code", True)
            self.assertEqual(invalid.exception.status, 401)
        with self.assertRaises(IdentityAuthError) as limited:
            self.service.identity_auth.complete_enrollment(principal, "not-a-code", True)
        self.assertEqual(limited.exception.status, 429)

    def test_step_up_guess_budget_is_database_backed(self) -> None:
        user = self._activate_and_enroll("Stepup.User")
        principal = self.service.identity_auth.validate_session(user["ordinary"].token)
        for _ in range(5):
            with self.assertRaises(IdentityAuthError) as invalid:
                self.service.identity_auth.step_up(principal, str(user["password"]), "not-a-code")
            self.assertEqual(invalid.exception.status, 401)
        with self.assertRaises(IdentityAuthError) as limited:
            self.service.identity_auth.step_up(principal, str(user["password"]), "not-a-code")
        self.assertEqual(limited.exception.status, 429)

    def test_wsgi_v2_bootstrap_needs_no_legacy_okx_or_admin_secrets(self) -> None:
        environment = {
            "MULTIUSER_ENABLED": "true",
            "MULTIUSER_DATABASE_URL": "postgresql://identity-test.invalid/multiuser",
            "SESSION_SIGNING_KEY": (b"s" * 32).hex(),
            "CREDENTIAL_VAULT_KEY": base64.b64encode(b"v" * 32).decode("ascii"),
            "CREDENTIAL_VAULT_KEY_ID": "v1-test",
            "REMOTE_IDENTITY_KEY": base64.b64encode(b"r" * 32).decode("ascii"),
            "ALLOWED_WEB_ORIGIN": "https://tradingbalancef.example",
        }
        with patch.dict(os.environ, environment, clear=True):
            service = WSGIApplication()._get_service()
        self.assertTrue(service.settings.multiuser_enabled)
        self.assertEqual(service.settings.allowed_web_origin, environment["ALLOWED_WEB_ORIGIN"])
        self.assertEqual(service.settings.okx_api_key, "")
        self.assertEqual(service.settings.admin_password_hash, "")

    def test_aes_gcm_owner_aad_and_tamper_fail_closed_when_available(self) -> None:
        try:
            import cryptography  # noqa: F401
        except ImportError:
            self.skipTest("BLOCKED: cryptography is not installed in this runtime")
        cipher = AesGCMSeedCipher(b"v" * 32, "key-v1")
        nonce, ciphertext = cipher.encrypt("owner-a", "TOTPSEED")
        self.assertEqual(cipher.decrypt("owner-a", "key-v1", nonce, ciphertext), "TOTPSEED")
        with self.assertRaises(CryptoInvalidCiphertext):
            cipher.decrypt("owner-b", "key-v1", nonce, ciphertext)
        mutated = ciphertext[:-1] + bytes([ciphertext[-1] ^ 1])
        with self.assertRaises(CryptoInvalidCiphertext):
            cipher.decrypt("owner-a", "key-v1", nonce, mutated)


if __name__ == "__main__":
    unittest.main()
