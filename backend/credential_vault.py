"""Purpose-separated AES-GCM vault for owner-bound exchange credentials."""

from __future__ import annotations

import json
import secrets
from typing import Any

from .security import CryptoInvalidCiphertext, CryptoUnavailable


class CredentialVault:
    """Encrypt exchange secrets and remote identities with explicit AAD."""

    _KEY_LENGTH = 32
    _NONCE_LENGTH = 12

    def __init__(self, master_key: bytes, key_id: str):
        if not isinstance(master_key, bytes) or len(master_key) != self._KEY_LENGTH:
            raise ValueError("credential vault key must be 32 bytes")
        if not isinstance(key_id, str) or not key_id or len(key_id) > 64:
            raise ValueError("credential vault key id is invalid")
        self._master_key = bytes(master_key)
        self.key_id = key_id

    def _aead(self, purpose: bytes) -> Any:
        try:
            from cryptography.hazmat.primitives import hashes
            from cryptography.hazmat.primitives.ciphers.aead import AESGCM
            from cryptography.hazmat.primitives.kdf.hkdf import HKDF
        except ImportError:
            raise CryptoUnavailable("the AES-GCM runtime dependency is unavailable") from None
        key = HKDF(
            algorithm=hashes.SHA256(),
            length=self._KEY_LENGTH,
            salt=None,
            info=b"trading-balance-f/credential-vault/v1/" + purpose,
        ).derive(self._master_key)
        return AESGCM(key)

    def _aad(
        self,
        purpose: str,
        *,
        user_id: str,
        connection_id: str,
        exchange: str,
        credential_version: int,
        environment: str,
        region: str,
    ) -> bytes:
        if not all(isinstance(value, str) and value for value in (
            user_id, connection_id, exchange, environment, region
        )):
            raise ValueError("credential owner context is incomplete")
        if isinstance(credential_version, bool) or not isinstance(credential_version, int) or credential_version < 1:
            raise ValueError("credential version is invalid")
        context = {
            "connectionId": connection_id,
            "credentialVersion": credential_version,
            "environment": environment,
            "exchange": exchange,
            "keyId": self.key_id,
            "purpose": purpose,
            "region": region,
            "userId": user_id,
            "version": 1,
        }
        return json.dumps(context, sort_keys=True, separators=(",", ":")).encode("utf-8")

    def encrypt_credentials(
        self,
        credentials: dict[str, Any],
        *,
        user_id: str,
        connection_id: str,
        exchange: str,
        credential_version: int,
        environment: str,
        region: str,
    ) -> tuple[bytes, bytes]:
        if not isinstance(credentials, dict) or set(credentials) != {"apiKey", "apiSecret", "passphrase"}:
            raise ValueError("typed exchange credentials are required")
        normalized: dict[str, str] = {}
        limits = {"apiKey": 256, "apiSecret": 512, "passphrase": 256}
        for name, limit in limits.items():
            value = credentials[name]
            if not isinstance(value, str) or not value or len(value) > limit:
                raise ValueError("typed exchange credentials are invalid")
            try:
                value.encode("ascii")
            except UnicodeEncodeError:
                raise ValueError("typed exchange credentials are invalid") from None
            normalized[name] = value
        payload = json.dumps(normalized, sort_keys=True, separators=(",", ":")).encode("ascii")
        aad = self._aad(
            "credentials", user_id=user_id, connection_id=connection_id, exchange=exchange,
            credential_version=credential_version, environment=environment, region=region,
        )
        nonce = secrets.token_bytes(self._NONCE_LENGTH)
        return nonce, self._aead(b"api-credentials").encrypt(nonce, payload, aad)

    def decrypt_credentials(
        self,
        key_id: str,
        nonce: bytes,
        ciphertext: bytes,
        *,
        user_id: str,
        connection_id: str,
        exchange: str,
        credential_version: int,
        environment: str,
        region: str,
    ) -> dict[str, str]:
        if key_id != self.key_id or len(nonce) != self._NONCE_LENGTH or len(ciphertext) < 16:
            raise CryptoInvalidCiphertext("credential ciphertext is invalid")
        aad = self._aad(
            "credentials", user_id=user_id, connection_id=connection_id, exchange=exchange,
            credential_version=credential_version, environment=environment, region=region,
        )
        try:
            plaintext = self._aead(b"api-credentials").decrypt(nonce, ciphertext, aad)
            decoded = json.loads(plaintext.decode("ascii"))
        except CryptoUnavailable:
            raise
        except Exception:
            raise CryptoInvalidCiphertext("credential ciphertext is invalid") from None
        if not isinstance(decoded, dict) or set(decoded) != {"apiKey", "apiSecret", "passphrase"}:
            raise CryptoInvalidCiphertext("credential ciphertext is invalid")
        if any(not isinstance(value, str) for value in decoded.values()):
            raise CryptoInvalidCiphertext("credential ciphertext is invalid")
        return decoded

    def encrypt_remote_identity(
        self,
        remote_uid: str,
        *,
        user_id: str,
        connection_id: str,
        exchange: str,
        environment: str,
        region: str,
    ) -> tuple[bytes, bytes]:
        if not isinstance(remote_uid, str) or not remote_uid or len(remote_uid) > 128:
            raise ValueError("remote identity is invalid")
        aad = self._aad(
            "remote-identity", user_id=user_id, connection_id=connection_id, exchange=exchange,
            credential_version=1, environment=environment, region=region,
        )
        nonce = secrets.token_bytes(self._NONCE_LENGTH)
        return nonce, self._aead(b"remote-identity").encrypt(nonce, remote_uid.encode("ascii"), aad)

    def decrypt_remote_identity(
        self,
        key_id: str,
        nonce: bytes,
        ciphertext: bytes,
        *,
        user_id: str,
        connection_id: str,
        exchange: str,
        environment: str,
        region: str,
    ) -> str:
        if key_id != self.key_id or len(nonce) != self._NONCE_LENGTH or len(ciphertext) < 16:
            raise CryptoInvalidCiphertext("remote identity ciphertext is invalid")
        aad = self._aad(
            "remote-identity", user_id=user_id, connection_id=connection_id, exchange=exchange,
            credential_version=1, environment=environment, region=region,
        )
        try:
            value = self._aead(b"remote-identity").decrypt(nonce, ciphertext, aad).decode("ascii")
        except CryptoUnavailable:
            raise
        except Exception:
            raise CryptoInvalidCiphertext("remote identity ciphertext is invalid") from None
        if not value or len(value) > 128:
            raise CryptoInvalidCiphertext("remote identity ciphertext is invalid")
        return value
