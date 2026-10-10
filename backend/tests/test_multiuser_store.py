from __future__ import annotations

import hashlib
import multiprocessing
import os
import secrets
import unittest
from tempfile import TemporaryDirectory

from backend.auth import IdentityAuthError, IdentityAuthService
from backend.security import CryptoInvalidCiphertext, _totp_at
from backend.store import SQLiteIdentityStore
from backend.store_contract import IdentityStoreConflict


class _FabricatedSeedCipher:
    """Test-only cipher double; PostgreSQL tests cover storage concurrency only."""

    key_id = "test-fabricated"

    def encrypt(self, user_id: str, secret: str) -> tuple[bytes, bytes]:
        return b"nonce", user_id.encode() + b"\x00" + secret.encode("ascii")

    def decrypt(self, user_id: str, key_id: str, nonce: bytes, ciphertext: bytes) -> str:
        prefix = user_id.encode() + b"\x00"
        if key_id != self.key_id or not ciphertext.startswith(prefix):
            raise CryptoInvalidCiphertext("test seed mismatch")
        return ciphertext[len(prefix):].decode("ascii")


def _postgres_login_worker(
    dsn: str,
    signing_key: bytes,
    barrier: multiprocessing.synchronize.Barrier,
    result_queue: multiprocessing.queues.Queue,
    username: str,
    password: str,
    totp: str,
    now: float,
) -> None:
    from backend.postgres_store import PostgresIdentityStore

    auth = IdentityAuthService(
        PostgresIdentityStore(dsn),
        signing_key,
        _FabricatedSeedCipher(),
        clock=lambda: now,
    )
    try:
        barrier.wait(timeout=15)
        issued = auth.login(username, password, totp=totp, source="203.0.113.44")
        result_queue.put(("ok", issued.user_id))
    except IdentityAuthError as error:
        result_queue.put(("denied", error.status))
    except BaseException as error:  # Send a safe type marker to the parent test.
        result_queue.put(("failure", type(error).__name__))


def _postgres_recovery_worker(
    dsn: str,
    signing_key: bytes,
    barrier: multiprocessing.synchronize.Barrier,
    result_queue: multiprocessing.queues.Queue,
    username: str,
    password: str,
    recovery_code: str,
    now: float,
) -> None:
    from backend.postgres_store import PostgresIdentityStore

    auth = IdentityAuthService(
        PostgresIdentityStore(dsn), signing_key, _FabricatedSeedCipher(), clock=lambda: now
    )
    try:
        barrier.wait(timeout=15)
        issued = auth.login(
            username, password, recovery_code=recovery_code, source="203.0.113.45"
        )
        result_queue.put(("recovery", "ok", issued.user_id))
    except IdentityAuthError as error:
        result_queue.put(("recovery", "denied", error.status))
    except BaseException as error:
        result_queue.put(("recovery", "failure", type(error).__name__))


def _postgres_enrollment_completion_worker(
    dsn: str,
    signing_key: bytes,
    barrier: multiprocessing.synchronize.Barrier,
    result_queue: multiprocessing.queues.Queue,
    session_token: str,
    totp: str,
    now: float,
) -> None:
    from backend.postgres_store import PostgresIdentityStore

    auth = IdentityAuthService(
        PostgresIdentityStore(dsn), signing_key, _FabricatedSeedCipher(), clock=lambda: now
    )
    try:
        principal = auth.validate_session(session_token)
        barrier.wait(timeout=15)
        auth.complete_enrollment(principal, totp, True)
        result_queue.put(("completion", "ok"))
    except IdentityAuthError as error:
        result_queue.put(("completion", "denied", error.status))
    except BaseException as error:
        result_queue.put(("completion", "failure", type(error).__name__))


class SQLiteIdentityStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = TemporaryDirectory()
        self.store = SQLiteIdentityStore(f"{self.temp.name}/identity.sqlite3")
        self.store.initialize()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_sqlite_staging_enables_foreign_keys_and_owner_composite_keys(self) -> None:
        with self.store.connection() as connection:
            foreign_keys = connection.execute("PRAGMA foreign_keys").fetchone()[0]
            version = connection.execute(
                "SELECT version FROM multiuser_schema_version WHERE singleton=1"
            ).fetchone()[0]
        self.assertEqual(foreign_keys, 1)
        self.assertEqual(version, 1)
        with self.assertRaises(IdentityStoreConflict):
            with self.store.transaction() as connection:
                connection.execute(
                    "INSERT INTO user_invites(invite_id, token_hash, created_at, expires_at, activated_user_id) "
                    "VALUES (?, ?, ?, ?, ?)",
                    ("invite-orphan", "hash-orphan", 1, 100, "missing-user"),
                )

        with self.store.transaction() as connection:
            for user_id in ("owner-a", "owner-b"):
                connection.execute(
                    "INSERT INTO users(user_id, username, username_normalized, password_hash, status, auth_version, created_at) "
                    "VALUES (?, ?, ?, ?, 'ACTIVE', 1, ?)",
                    (user_id, user_id, user_id, "test-hash", 1),
                )
            connection.execute(
                "INSERT INTO exchange_connections(user_id, connection_id, exchange, environment, region, status, "
                "remote_identity_digest, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                ("owner-a", "connection-a", "OKX", "live", "global", "ACTIVE", "remote-digest", 1, 1),
            )
        with self.assertRaises(IdentityStoreConflict):
            with self.store.transaction() as connection:
                connection.execute(
                    "INSERT INTO multiuser_operations(user_id, connection_id, operation_id, product, "
                    "idempotency_key, request_hash, status, created_at, updated_at) "
                    "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    ("owner-b", "connection-a", "operation-1", "SWAP", "key-1", "hash-1", "NEW", 1, 1),
                )


class PostgresIdentityStoreIntegrationTests(unittest.TestCase):
    @staticmethod
    def _create_test_user(test_dsn: str, psycopg: object, now: float) -> tuple[str, str, object, str, str, list[str], str]:
        schema = "t110_" + secrets.token_hex(8)
        with psycopg.connect(test_dsn, autocommit=True) as connection:
            connection.execute(f'CREATE SCHEMA "{schema}"')
        schema_dsn = psycopg.conninfo.make_conninfo(
            test_dsn, options=f"-c search_path={schema}"
        )
        from backend.postgres_store import PostgresIdentityStore

        store = PostgresIdentityStore(schema_dsn)
        store.initialize()
        signing_key = b"P" * 32
        auth = IdentityAuthService(store, signing_key, _FabricatedSeedCipher(), clock=lambda: now)
        _, invite = auth.create_invite()
        username = "Postgres.User"
        password = "multi-process postgres test password"
        activated = auth.activate_invite(invite, username, password, "203.0.113.43")
        enrollment_principal = auth.validate_session(activated.token)
        challenge = auth.start_enrollment(enrollment_principal)
        secret = str(challenge["totpSecret"])
        enrollment_code = _totp_at(secret, int(now // 30))
        auth.complete_enrollment(enrollment_principal, enrollment_code, True)
        ordinary = auth.login(
            username,
            password,
            totp=_totp_at(secret, int((now + 30) // 30)),
            source="203.0.113.43",
        )
        return (
            schema,
            schema_dsn,
            auth,
            username,
            password,
            [str(value) for value in challenge["recoveryCodes"]],
            ordinary.token,
        )

    def _require_test_dsn(self) -> tuple[str, object]:
        test_dsn = os.environ.get("MULTIUSER_TEST_DATABASE_URL", "")
        if not test_dsn:
            self.skipTest("BLOCKED: MULTIUSER_TEST_DATABASE_URL is not configured")
        try:
            import psycopg
        except ImportError:
            self.fail("BLOCKED: psycopg is required when MULTIUSER_TEST_DATABASE_URL is configured")
        return test_dsn, psycopg

    def _stored_mfa_seed(self, auth: IdentityAuthService, user_id: str) -> str:
        with auth.store.connection() as connection:
            mfa = connection.execute(
                "SELECT key_id, nonce, ciphertext FROM user_mfa WHERE user_id=?", (user_id,)
            ).fetchone()
        self.assertIsNotNone(mfa)
        return auth._require_cipher().decrypt(
            user_id, mfa["key_id"], bytes(mfa["nonce"]), bytes(mfa["ciphertext"])
        )

    def _assert_recovery_material(
        self,
        connection: object,
        user_id: str,
        recovery_codes: list[str],
        consumed_codes: set[str] | None = None,
    ) -> None:
        expected: dict[str, str] = {}
        for code in recovery_codes:
            parsed = IdentityAuthService._split_recovery_code(code)
            self.assertIsNotNone(parsed)
            code_id, secret = parsed
            expected[code_id] = secret
        rows = connection.execute(
            "SELECT code_id, code_salt, code_hash, consumed_at FROM user_recovery_codes WHERE user_id=?",
            (user_id,),
        ).fetchall()
        actual = {str(row["code_id"]): row for row in rows}
        self.assertEqual(set(actual), set(expected))
        consumed = consumed_codes or set()
        for code_id, secret in expected.items():
            row = actual[code_id]
            self.assertEqual(
                bytes(row["code_hash"]),
                hashlib.sha256(bytes(row["code_salt"]) + secret.encode("utf-8")).digest(),
            )
            self.assertEqual(row["consumed_at"] is not None, code_id in consumed)

    def test_replayed_totp_is_single_use_across_processes_and_connections(self) -> None:
        # Only this dedicated input authorizes a temporary schema. There is no
        # fallback to the production/runtime MULTIUSER_DATABASE_URL.
        test_dsn = os.environ.get("MULTIUSER_TEST_DATABASE_URL", "")
        if not test_dsn:
            self.skipTest("BLOCKED: MULTIUSER_TEST_DATABASE_URL is not configured")
        try:
            import psycopg
        except ImportError:
            self.fail("BLOCKED: psycopg is required when MULTIUSER_TEST_DATABASE_URL is configured")

        schema = "t110_" + secrets.token_hex(8)
        signing_key = b"P" * 32
        now = 1_800_000_000.0
        schema_created = False
        processes: list[multiprocessing.Process] = []
        queue: multiprocessing.queues.Queue | None = None
        try:
            with psycopg.connect(test_dsn, autocommit=True) as connection:
                connection.execute(f'CREATE SCHEMA "{schema}"')
            schema_created = True
            test_schema_dsn = psycopg.conninfo.make_conninfo(
                test_dsn, options=f"-c search_path={schema}"
            )
            from backend.postgres_store import PostgresIdentityStore

            store = PostgresIdentityStore(test_schema_dsn)
            store.initialize()
            auth = IdentityAuthService(
                store, signing_key, _FabricatedSeedCipher(), clock=lambda: now
            )
            _, invite = auth.create_invite()
            password = "multi-process postgres test password"
            activated = auth.activate_invite(invite, "Postgres.User", password, "203.0.113.43")
            enrollment_principal = auth.validate_session(activated.token)
            challenge = auth.start_enrollment(enrollment_principal)
            secret = str(challenge["totpSecret"])
            enrollment_code = _totp_at(secret, int(now // 30))
            auth.complete_enrollment(enrollment_principal, enrollment_code, True)
            now += 30
            login_code = _totp_at(secret, int(now // 30))

            context = multiprocessing.get_context("spawn")
            barrier = context.Barrier(2)
            queue = context.Queue()
            for _ in range(2):
                process = context.Process(
                    target=_postgres_login_worker,
                    args=(
                        test_schema_dsn,
                        signing_key,
                        barrier,
                        queue,
                        "Postgres.User",
                        password,
                        login_code,
                        now,
                    ),
                )
                processes.append(process)
                process.start()
            results = [queue.get(timeout=45) for _ in processes]
            for process in processes:
                process.join(timeout=45)
                self.assertEqual(process.exitcode, 0)
            self.assertEqual(sum(result[0] == "ok" for result in results), 1, results)
            self.assertEqual(results.count(("denied", 401)), 1, results)
        finally:
            for process in processes:
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
            if queue is not None:
                queue.close()
            if schema_created:
                with psycopg.connect(test_dsn, autocommit=True) as connection:
                    connection.execute(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')

    def test_recovery_code_is_single_use_across_processes_and_revokes_old_session(self) -> None:
        test_dsn, psycopg = self._require_test_dsn()
        now = 1_800_000_000.0
        schema, schema_dsn, auth, username, password, recovery_codes, ordinary_token = self._create_test_user(
            test_dsn, psycopg, now
        )
        processes: list[multiprocessing.Process] = []
        queue: multiprocessing.queues.Queue | None = None
        try:
            context = multiprocessing.get_context("spawn")
            barrier = context.Barrier(2)
            queue = context.Queue()
            for _ in range(2):
                process = context.Process(
                    target=_postgres_recovery_worker,
                    args=(
                        schema_dsn,
                        b"P" * 32,
                        barrier,
                        queue,
                        username,
                        password,
                        recovery_codes[0],
                        now + 30,
                    ),
                )
                processes.append(process)
                process.start()
            results = [queue.get(timeout=45) for _ in processes]
            for process in processes:
                process.join(timeout=45)
                self.assertEqual(process.exitcode, 0)
            self.assertEqual(sum(result[:2] == ("recovery", "ok") for result in results), 1, results)
            self.assertEqual(results.count(("recovery", "denied", 401)), 1, results)
            with self.assertRaises(IdentityAuthError) as old_session:
                auth.validate_session(ordinary_token)
            self.assertEqual(old_session.exception.status, 401)
        finally:
            for process in processes:
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
            if queue is not None:
                queue.close()
            with psycopg.connect(test_dsn, autocommit=True) as connection:
                connection.execute(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')

    def test_concurrent_enrollment_completion_and_recovery_are_serialized(self) -> None:
        test_dsn, psycopg = self._require_test_dsn()
        now = 1_800_000_000.0
        schema, schema_dsn, auth, username, password, recovery_codes, ordinary_token = self._create_test_user(
            test_dsn, psycopg, now
        )
        processes: list[multiprocessing.Process] = []
        queue: multiprocessing.queues.Queue | None = None
        try:
            recovery = auth.login(
                username,
                password,
                recovery_code=recovery_codes[0],
                source="203.0.113.46",
            )
            recovery_principal = auth.validate_session(recovery.token)
            challenge = auth.start_enrollment(recovery_principal)
            completion_code = _totp_at(str(challenge["totpSecret"]), int(now // 30))
            original_seed = self._stored_mfa_seed(auth, recovery.user_id)
            context = multiprocessing.get_context("spawn")
            barrier = context.Barrier(2)
            queue = context.Queue()
            completion = context.Process(
                target=_postgres_enrollment_completion_worker,
                args=(schema_dsn, b"P" * 32, barrier, queue, recovery.token, completion_code, now),
            )
            recovery_process = context.Process(
                target=_postgres_recovery_worker,
                args=(
                    schema_dsn,
                    b"P" * 32,
                    barrier,
                    queue,
                    username,
                    password,
                    recovery_codes[1],
                    now,
                ),
            )
            processes.extend((completion, recovery_process))
            for process in processes:
                process.start()
            results = [queue.get(timeout=45) for _ in processes]
            for process in processes:
                process.join(timeout=45)
                self.assertEqual(process.exitcode, 0)
            self.assertEqual(len(results), 2, results)
            self.assertEqual({result[0] for result in results}, {"completion", "recovery"}, results)
            results_by_worker = {result[0]: result[1:] for result in results}
            completion_result = results_by_worker["completion"]
            recovery_result = results_by_worker["recovery"]
            if completion_result == ("ok",) and recovery_result == ("denied", 401):
                winner = "completion"
            elif completion_result == ("denied", 401) and recovery_result == ("ok", recovery.user_id):
                winner = "recovery"
            else:
                self.fail(f"unsafe enrollment/recovery race outcome: {results!r}")
            with self.assertRaises(IdentityAuthError) as stale_recovery_session:
                auth.validate_session(recovery.token)
            self.assertEqual(stale_recovery_session.exception.status, 401)
            with self.assertRaises(IdentityAuthError) as old_ordinary_session:
                auth.validate_session(ordinary_token)
            self.assertEqual(old_ordinary_session.exception.status, 401)
            with auth.store.connection() as connection:
                user = connection.execute(
                    "SELECT user_id, status FROM users WHERE username_normalized=?", (username.lower(),)
                ).fetchone()
                if winner == "completion":
                    self.assertEqual(user["status"], "ACTIVE")
                    self.assertEqual(self._stored_mfa_seed(auth, user["user_id"]), challenge["totpSecret"])
                    self._assert_recovery_material(connection, user["user_id"], challenge["recoveryCodes"])
                else:
                    self.assertEqual(user["status"], "MFA_RECOVERY")
                    self.assertEqual(self._stored_mfa_seed(auth, user["user_id"]), original_seed)
                    consumed_ids = {
                        IdentityAuthService._split_recovery_code(code)[0]
                        for code in recovery_codes[:2]
                    }
                    self._assert_recovery_material(
                        connection, user["user_id"], recovery_codes, consumed_ids
                    )
        finally:
            for process in processes:
                if process.is_alive():
                    process.terminate()
                    process.join(timeout=5)
            if queue is not None:
                queue.close()
            with psycopg.connect(test_dsn, autocommit=True) as connection:
                connection.execute(f'DROP SCHEMA IF EXISTS "{schema}" CASCADE')


if __name__ == "__main__":
    unittest.main()
