#!/usr/bin/env python3
"""Dev test user creation script.

Usage:
    python create_dev_user.py
    python create_dev_user.py --email test@example.com --password secret123
    python create_dev_user.py --count 5
    python create_dev_user.py --list
    python create_dev_user.py --delete test@example.com

Defaults:
    email   : dev{N}@chorus.local  (N = 1, 2, ...)
    password: devpass123
"""

import os
import sys
import argparse
import sqlite3
from datetime import datetime, timedelta, timezone

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(BASE_DIR)
sys.path.insert(0, BASE_DIR)

# ──────────────────────────────────────────────
# Load .env
# ──────────────────────────────────────────────
try:
    from dotenv import load_dotenv
    load_dotenv(os.path.join(BASE_DIR, ".env"))
except ImportError:
    # Manual parsing if python-dotenv is not installed
    env_path = os.path.join(BASE_DIR, ".env")
    if os.path.exists(env_path):
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    os.environ.setdefault(k.strip(), v.strip())

DB_TYPE    = os.environ.get("DB_TYPE", "sqlite3").lower()
DB_PATH    = os.environ.get("DB_PATH", "chorus.db")
SECRET_KEY = os.environ.get("SECRET_KEY", "")
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.environ.get("ACCESS_TOKEN_EXPIRE_MINUTES", "30"))

# ──────────────────────────────────────────────
# Import dependencies (using same libraries as the server)
# ──────────────────────────────────────────────
try:
    from passlib.context import CryptContext
    pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")
    def hash_password(pw: str) -> str:
        return pwd_context.hash(pw)
except ImportError:
    import hashlib
    def hash_password(pw: str) -> str:  # type: ignore[misc]
        return hashlib.sha256(pw.encode()).hexdigest()

try:
    import jwt as pyjwt
    def make_token(user_id: str) -> str:
        expire = datetime.now(timezone.utc) + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
        return pyjwt.encode({"sub": user_id, "exp": expire}, SECRET_KEY, algorithm="HS256")
except ImportError:
    def make_token(user_id: str) -> str:  # type: ignore[misc]
        return "(pyjwt not installed — cannot generate JWT)"


# ──────────────────────────────────────────────
# SQLite-only helper
# ──────────────────────────────────────────────
USERS_DDL = """
CREATE TABLE IF NOT EXISTS users (
    user_id        TEXT PRIMARY KEY,
    password       TEXT NOT NULL,
    email_verified INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT NOT NULL
);
"""

def get_conn() -> sqlite3.Connection:
    db_path = DB_PATH if os.path.isabs(DB_PATH) else os.path.join(BASE_DIR, DB_PATH)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    return conn


def ensure_users_table(conn: sqlite3.Connection) -> None:
    conn.execute(USERS_DDL)
    conn.commit()


def user_exists(conn: sqlite3.Connection, user_id: str) -> bool:
    row = conn.execute("SELECT 1 FROM users WHERE user_id = ?", (user_id,)).fetchone()
    return row is not None


def create_user(conn: sqlite3.Connection, user_id: str, password: str) -> dict:
    hashed = hash_password(password)
    now    = datetime.now(timezone.utc).isoformat()
    conn.execute(
        "INSERT INTO users (user_id, password, email_verified, created_at) VALUES (?, ?, 1, ?)",
        (user_id, hashed, now),
    )
    conn.commit()
    return {"user_id": user_id, "password": password, "token": make_token(user_id)}


def list_users(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        "SELECT user_id, email_verified, created_at FROM users ORDER BY created_at"
    ).fetchall()
    return [dict(r) for r in rows]


def delete_user(conn: sqlite3.Connection, user_id: str) -> bool:
    cur = conn.execute("DELETE FROM users WHERE user_id = ?", (user_id,))
    conn.commit()
    return cur.rowcount > 0


# ──────────────────────────────────────────────
# Output helper
# ──────────────────────────────────────────────
def print_user(info: dict, idx: int = 1) -> None:
    print(f"\n  [{idx}] user created")
    print(f"      email   : {info['user_id']}")
    print(f"      password: {info['password']}")
    print(f"      token   : {info['token']}")


# ──────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Dev test user creation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--email",    help="Email address to create (default: dev1@chorus.local)")
    p.add_argument("--password", default="devpass123", help="Password (default: devpass123)")
    p.add_argument("--count",    type=int, default=1, metavar="N",
                   help="Number of users to create — auto-generates dev1~devN if --email is not set")
    p.add_argument("--list",     action="store_true", help="Print list of registered users")
    p.add_argument("--delete",   metavar="EMAIL", help="Delete the specified user")
    p.add_argument("--token",    metavar="EMAIL", help="Re-issue JWT token for an existing user")
    return p


def main() -> None:
    args = build_parser().parse_args()

    if DB_TYPE not in ("sqlite", "sqlite3", "local"):
        print(f"[!] This script only works with SQLite DB. (current DB_TYPE={DB_TYPE})")
        print("    For MySQL/PostgreSQL, please use the server Register API.")
        sys.exit(1)

    conn = get_conn()
    ensure_users_table(conn)

    # ── List
    if args.list:
        users = list_users(conn)
        if not users:
            print("No registered users.")
        else:
            print(f"{'Email':<35} {'Verified':<8} {'Created at'}")
            print("-" * 70)
            for u in users:
                verified = "✅" if u["email_verified"] else "❌"
                print(f"{u['user_id']:<35} {verified:<6} {u['created_at'][:19]}")
        conn.close()
        return

    # ── Delete
    if args.delete:
        if delete_user(conn, args.delete):
            print(f"✅ User deleted: {args.delete}")
        else:
            print(f"[!] User not found: {args.delete}")
        conn.close()
        return

    # ── Re-issue token
    if args.token:
        if user_exists(conn, args.token):
            token = make_token(args.token)
            print(f"\n  email : {args.token}")
            print(f"  token : {token}")
        else:
            print(f"[!] User not found: {args.token}")
        conn.close()
        return

    # ── Create
    emails: list[str] = []
    if args.email:
        emails = [args.email]
    else:
        emails = [f"dev{i}@chorus.local" for i in range(1, args.count + 1)]

    print(f"\n🚀 Creating dev test users (DB: {DB_PATH})")
    created, skipped = [], []

    for idx, email in enumerate(emails, start=1):
        if user_exists(conn, email):
            skipped.append(email)
            print(f"  [skip] user already exists: {email}")
            continue
        info = create_user(conn, email, args.password)
        created.append(info)
        print_user(info, idx)

    conn.close()

    print(f"\nDone: {len(created)} created, {len(skipped)} skipped")
    if not SECRET_KEY:
        print("\n⚠️  SECRET_KEY is not set in .env. Tokens may be invalid.")


if __name__ == "__main__":
    main()
