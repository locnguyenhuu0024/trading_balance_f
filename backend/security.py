"""Password, TOTP, and opaque-token helpers for the private API."""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import struct
import time
from typing import Protocol


SCRYPT_N = 2**15
SCRYPT_R = 8
SCRYPT_P = 1
SCRYPT_MAXMEM = 128 * 1024 * 1024


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def hash_password(password: str, *, salt: bytes | None = None) -> str:
    if len(password) < 16:
        raise ValueError("password must contain at least 16 characters")
    actual_salt = secrets.token_bytes(16) if salt is None else salt
    derived = hashlib.scrypt(
        password.encode("utf-8"),
        salt=actual_salt,
        n=SCRYPT_N,
        r=SCRYPT_R,
        p=SCRYPT_P,
        dklen=32,
        maxmem=SCRYPT_MAXMEM,
    )
    return f"scrypt${SCRYPT_N}${SCRYPT_R}${SCRYPT_P}${_b64(actual_salt)}${_b64(derived)}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        algorithm, n_text, r_text, p_text, salt_text, digest_text = encoded.split("$", 5)
        n, r, p = int(n_text), int(r_text), int(p_text)
        if algorithm != "scrypt" or not (2**12 <= n <= 2**18 and n & (n - 1) == 0):
            return False
        if not (1 <= r <= 16 and 1 <= p <= 4):
            return False
        salt = base64.urlsafe_b64decode(salt_text + "===")
        expected = base64.urlsafe_b64decode(digest_text + "===")
        if not (16 <= len(salt) <= 64 and len(expected) == 32):
            return False
        candidate = hashlib.scrypt(
            password.encode("utf-8"),
            salt=salt,
            n=n,
            r=r,
            p=p,
            dklen=len(expected),
            maxmem=SCRYPT_MAXMEM,
        )
        return hmac.compare_digest(candidate, expected)
    except (ValueError, TypeError, UnicodeError):
        return False


def generate_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def generate_session_signing_key() -> str:
    return secrets.token_bytes(32).hex()


def _totp_at(secret: str, counter: int) -> str:
    normalized = secret.replace(" ", "").upper()
    key = base64.b32decode(normalized + "=" * ((8 - len(normalized) % 8) % 8), casefold=True)
    digest = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    value = (struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF) % 1_000_000
    return f"{value:06d}"


def matching_totp_counter(secret: str, code: str, timestamp: float, last_counter: int) -> int | None:
    if len(code) != 6 or not code.isascii() or not code.isdigit():
        hmac.compare_digest("000000", "999999")
        return None
    current = int(timestamp // 30)
    matches: list[int] = []
    for counter in (current - 1, current, current + 1):
        if counter <= last_counter or counter < 0:
            continue
        if hmac.compare_digest(_totp_at(secret, counter), code):
            matches.append(counter)
    return max(matches) if matches else None


def token_digest(token: str, signing_key: bytes) -> str:
    return hmac.new(signing_key, token.encode("utf-8"), hashlib.sha256).hexdigest()


def new_bearer_token() -> str:
    return secrets.token_urlsafe(32)


def new_operation_id() -> str:
    return secrets.token_hex(16)


def new_confirmation_token() -> str:
    return secrets.token_urlsafe(32)


def current_time() -> float:
    return time.time()


class SeedCipher(Protocol):
    """Purpose-separated encryption interface for per-user MFA seeds."""

    key_id: str

    def encrypt(self, user_id: str, secret: str) -> tuple[bytes, bytes]: ...

    def decrypt(self, user_id: str, key_id: str, nonce: bytes, ciphertext: bytes) -> str: ...


class CryptoUnavailable(Exception):
    """The vetted AES-GCM runtime dependency is not installed."""


class CryptoInvalidCiphertext(Exception):
    """An encrypted MFA seed failed authenticated decryption."""


class AesGCMSeedCipher:
    """AES-GCM seed encryption with HKDF purpose separation and owner-bound AAD."""

    PURPOSE = b"trading-balance-f/mfa-seed/v1"

    def __init__(self, master_key: bytes, key_id: str):
        if len(master_key) != 32 or not key_id or len(key_id) > 64:
            raise ValueError("invalid MFA vault key configuration")
        self._master_key = bytes(master_key)
        self.key_id = key_id

    def _aead(self) -> object:
        try:
            from cryptography.hazmat.primitives import hashes
            from cryptography.hazmat.primitives.ciphers.aead import AESGCM
            from cryptography.hazmat.primitives.kdf.hkdf import HKDF
        except ImportError:
            raise CryptoUnavailable("the AES-GCM runtime dependency is unavailable") from None
        derived_key = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=hashlib.sha256(b"OptCodex-identity-v1").digest(),
            info=self.PURPOSE,
        ).derive(self._master_key)
        return AESGCM(derived_key)

    def _aad(self, user_id: str) -> bytes:
        if not user_id:
            raise ValueError("MFA seed owner is required")
        return b"optcodex\x00mfa-seed\x00v1\x00" + user_id.encode("utf-8") + b"\x00" + self.key_id.encode("ascii")

    def encrypt(self, user_id: str, secret: str) -> tuple[bytes, bytes]:
        aead = self._aead()
        nonce = secrets.token_bytes(12)
        ciphertext = aead.encrypt(nonce, secret.encode("ascii"), self._aad(user_id))
        return nonce, ciphertext

    def decrypt(self, user_id: str, key_id: str, nonce: bytes, ciphertext: bytes) -> str:
        if key_id != self.key_id or len(nonce) != 12:
            raise CryptoInvalidCiphertext("MFA seed key version is unavailable")
        try:
            from cryptography.exceptions import InvalidTag
            aead = self._aead()
        except ImportError:
            raise CryptoUnavailable("the AES-GCM runtime dependency is unavailable") from None
        try:
            secret = aead.decrypt(nonce, ciphertext, self._aad(user_id))
            return secret.decode("ascii")
        except (InvalidTag, ValueError, UnicodeError):
            raise CryptoInvalidCiphertext("MFA seed authentication failed") from None
