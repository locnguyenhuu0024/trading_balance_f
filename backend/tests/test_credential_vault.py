from __future__ import annotations

import unittest

from backend.credential_vault import CredentialVault
from backend.security import CryptoInvalidCiphertext, CryptoUnavailable


class CredentialVaultAesGcmTests(unittest.TestCase):
    """Runtime AES-GCM contract tests; operator verification must run without skips."""

    def setUp(self) -> None:
        self.vault = CredentialVault(b"V" * 32, "key-one")
        self.credentials = {
            "apiKey": "fabricated-api-key",
            "apiSecret": "fabricated-api-secret",
            "passphrase": "fabricated-passphrase",
        }
        self.owner = {
            "user_id": "user-a",
            "connection_id": "connection-a",
            "exchange": "OKX",
            "credential_version": 3,
            "environment": "demo",
            "region": "global",
        }

    def _encrypt_credentials(self) -> tuple[bytes, bytes]:
        try:
            return self.vault.encrypt_credentials(self.credentials, **self.owner)
        except CryptoUnavailable:
            self.skipTest("cryptography AES-GCM runtime is unavailable")

    def test_binance_schema_is_two_fields_and_rejects_okx_passphrase_without_crypto(self) -> None:
        fields, limits = CredentialVault._schema("BINANCE")
        self.assertEqual(fields, ("apiKey", "apiSecret"))
        self.assertEqual(limits, {"apiKey": 256, "apiSecret": 512})
        with self.assertRaisesRegex(ValueError, "typed exchange credentials"):
            self.vault.encrypt_credentials(
                {"apiKey": "fabricated-api-key", "apiSecret": "fabricated-api-secret", "passphrase": "extra"},
                **{**self.owner, "exchange": "BINANCE"},
            )

    def test_real_aes_gcm_round_trip_binds_owner_version_and_environment(self) -> None:
        nonce, ciphertext = self._encrypt_credentials()

        self.assertEqual(
            self.vault.decrypt_credentials("key-one", nonce, ciphertext, **self.owner),
            self.credentials,
        )
        for name, value in (
            ("user_id", "user-b"),
            ("connection_id", "connection-b"),
            ("exchange", "BINANCE"),
            ("credential_version", 4),
            ("environment", "live"),
            ("region", "regional"),
        ):
            altered = {**self.owner, name: value}
            with self.subTest(aad_field=name), self.assertRaises(CryptoInvalidCiphertext):
                self.vault.decrypt_credentials("key-one", nonce, ciphertext, **altered)

    def test_key_id_ciphertext_and_nonce_tampering_fail_closed(self) -> None:
        nonce, ciphertext = self._encrypt_credentials()

        with self.assertRaises(CryptoInvalidCiphertext):
            self.vault.decrypt_credentials("key-two", nonce, ciphertext, **self.owner)
        with self.assertRaises(CryptoInvalidCiphertext):
            self.vault.decrypt_credentials("key-one", nonce, ciphertext[:-1] + bytes([ciphertext[-1] ^ 1]), **self.owner)
        with self.assertRaises(CryptoInvalidCiphertext):
            self.vault.decrypt_credentials("key-one", bytes([nonce[0] ^ 1]) + nonce[1:], ciphertext, **self.owner)

    def test_credential_and_remote_identity_purposes_are_separate(self) -> None:
        nonce, ciphertext = self._encrypt_credentials()
        identity_nonce, identity_ciphertext = self.vault.encrypt_remote_identity(
            "fabricated-account-uid",
            user_id=self.owner["user_id"],
            connection_id=self.owner["connection_id"],
            exchange=self.owner["exchange"],
            environment=self.owner["environment"],
            region=self.owner["region"],
        )

        with self.assertRaises(CryptoInvalidCiphertext):
            self.vault.decrypt_remote_identity(
                "key-one", nonce, ciphertext,
                user_id=self.owner["user_id"], connection_id=self.owner["connection_id"],
                exchange=self.owner["exchange"], environment=self.owner["environment"],
                region=self.owner["region"],
            )
        with self.assertRaises(CryptoInvalidCiphertext):
            self.vault.decrypt_credentials(
                "key-one", identity_nonce, identity_ciphertext, **self.owner,
            )
        self.assertEqual(
            self.vault.decrypt_remote_identity(
                "key-one", identity_nonce, identity_ciphertext,
                user_id=self.owner["user_id"], connection_id=self.owner["connection_id"],
                exchange=self.owner["exchange"], environment=self.owner["environment"],
                region=self.owner["region"],
            ),
            "fabricated-account-uid",
        )

    def test_binance_two_field_envelope_binds_owner_version_and_purpose(self) -> None:
        credentials = {"apiKey": "fabricated-binance-key", "apiSecret": "fabricated-binance-secret"}
        owner = {**self.owner, "exchange": "BINANCE"}
        try:
            nonce, ciphertext = self.vault.encrypt_credentials(credentials, **owner)
        except CryptoUnavailable:
            self.skipTest("cryptography AES-GCM runtime is unavailable")
        self.assertEqual(
            self.vault.decrypt_credentials("key-one", nonce, ciphertext, **owner), credentials
        )
        for name, value in (
            ("user_id", "user-b"),
            ("connection_id", "connection-b"),
            ("credential_version", 4),
            ("environment", "live"),
            ("region", "regional"),
        ):
            with self.subTest(aad_field=name), self.assertRaises(CryptoInvalidCiphertext):
                self.vault.decrypt_credentials(
                    "key-one", nonce, ciphertext, **{**owner, name: value}
                )
        with self.assertRaises(CryptoInvalidCiphertext):
            self.vault.decrypt_credentials(
                "key-one", nonce, ciphertext[:-1] + bytes([ciphertext[-1] ^ 1]), **owner
            )

        identity_nonce, identity_ciphertext = self.vault.encrypt_remote_identity(
            "123456789", user_id=owner["user_id"], connection_id=owner["connection_id"],
            exchange="BINANCE", environment=owner["environment"], region=owner["region"],
        )
        with self.assertRaises(CryptoInvalidCiphertext):
            self.vault.decrypt_credentials(
                "key-one", identity_nonce, identity_ciphertext, **owner
            )


if __name__ == "__main__":
    unittest.main()
