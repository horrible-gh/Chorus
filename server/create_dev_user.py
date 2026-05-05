#!/usr/bin/env python3
"""개발용 테스트 유저 생성 스크립트.

사용법:
    python create_dev_user.py
    python create_dev_user.py --email test@example.com --password secret123
    python create_dev_user.py --count 5
    python create_dev_user.py --list
    python create_dev_user.py --delete test@example.com

기본값:
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
# .env 로드
# ──────────────────────────────────────────────
try:
    from dotenv import load_dotenv
    load_dotenv(os.path.join(BASE_DIR, ".env"))
except ImportError:
    # python-dotenv가 없으면 수동 파싱
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
# 의존성 임포트 (서버와 동일한 라이브러리 사용)
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
        return "(pyjwt 미설치 — JWT 생성 불가)"


# ──────────────────────────────────────────────
# SQLite 전용 헬퍼
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
# 출력 헬퍼
# ──────────────────────────────────────────────
def print_user(info: dict, idx: int = 1) -> None:
    print(f"\n  [{idx}] 유저 생성 완료")
    print(f"      email   : {info['user_id']}")
    print(f"      password: {info['password']}")
    print(f"      token   : {info['token']}")


# ──────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="개발용 테스트 유저 생성",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--email",    help="생성할 유저의 이메일 (기본: dev1@chorus.local)")
    p.add_argument("--password", default="devpass123", help="비밀번호 (기본: devpass123)")
    p.add_argument("--count",    type=int, default=1, metavar="N",
                   help="생성할 유저 수 — --email 미지정 시 dev1~devN 자동 생성")
    p.add_argument("--list",     action="store_true", help="등록된 유저 목록 출력")
    p.add_argument("--delete",   metavar="EMAIL", help="지정한 유저 삭제")
    p.add_argument("--token",    metavar="EMAIL", help="기존 유저의 JWT 토큰 재발급")
    return p


def main() -> None:
    args = build_parser().parse_args()

    if DB_TYPE not in ("sqlite", "sqlite3", "local"):
        print(f"[!] 이 스크립트는 SQLite DB에서만 동작합니다. (현재 DB_TYPE={DB_TYPE})")
        print("    MySQL/PostgreSQL 환경에서는 서버 Register API를 사용해 주세요.")
        sys.exit(1)

    conn = get_conn()
    ensure_users_table(conn)

    # ── 목록
    if args.list:
        users = list_users(conn)
        if not users:
            print("등록된 유저가 없습니다.")
        else:
            print(f"{'이메일':<35} {'인증':<6} {'생성일'}")
            print("-" * 70)
            for u in users:
                verified = "✅" if u["email_verified"] else "❌"
                print(f"{u['user_id']:<35} {verified:<6} {u['created_at'][:19]}")
        conn.close()
        return

    # ── 삭제
    if args.delete:
        if delete_user(conn, args.delete):
            print(f"✅ 유저 삭제 완료: {args.delete}")
        else:
            print(f"[!] 유저를 찾을 수 없습니다: {args.delete}")
        conn.close()
        return

    # ── 토큰 재발급
    if args.token:
        if user_exists(conn, args.token):
            token = make_token(args.token)
            print(f"\n  email : {args.token}")
            print(f"  token : {token}")
        else:
            print(f"[!] 유저를 찾을 수 없습니다: {args.token}")
        conn.close()
        return

    # ── 생성
    emails: list[str] = []
    if args.email:
        emails = [args.email]
    else:
        emails = [f"dev{i}@chorus.local" for i in range(1, args.count + 1)]

    print(f"\n🚀 개발용 테스트 유저 생성 (DB: {DB_PATH})")
    created, skipped = [], []

    for idx, email in enumerate(emails, start=1):
        if user_exists(conn, email):
            skipped.append(email)
            print(f"  [skip] 이미 존재하는 유저: {email}")
            continue
        info = create_user(conn, email, args.password)
        created.append(info)
        print_user(info, idx)

    conn.close()

    print(f"\n완료: {len(created)}개 생성, {len(skipped)}개 스킵")
    if not SECRET_KEY:
        print("\n⚠️  .env에 SECRET_KEY가 설정되지 않았습니다. 토큰이 유효하지 않을 수 있습니다.")


if __name__ == "__main__":
    main()
