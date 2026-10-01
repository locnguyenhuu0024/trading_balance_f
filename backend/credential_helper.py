"""Explicit user-run helper for generating server authentication values."""

from __future__ import annotations

import getpass
import sys

from .security import generate_session_signing_key, generate_totp_secret, hash_password


def main() -> int:
    password = getpass.getpass("Choose the admin password (at least 16 characters): ")
    confirmation = getpass.getpass("Re-enter the admin password: ")
    if password != confirmation:
        print("Passwords did not match.", file=sys.stderr)
        return 2
    try:
        password_hash = hash_password(password)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2

    # This command prints values only when a user explicitly runs it.
    # Automated tests do not call this entry point.
    print("Save these values directly into the user-owned server environment file:")
    print(f"ADMIN_PASSWORD_HASH={password_hash}")
    print(f"TOTP_SECRET={generate_totp_secret()}")
    print(f"SESSION_SIGNING_KEY={generate_session_signing_key()}")
    print("Store the TOTP seed in an authenticator and keep a protected recovery copy.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
