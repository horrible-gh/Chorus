from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr
import jwt
import redis as redis_lib
from datetime import datetime, timedelta, timezone
from config import settings, db, tfa
from slowapi import Limiter
from slowapi.util import get_remote_address

import os
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

limiter = Limiter(key_func=get_remote_address)

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
REFRESH_TOKEN_EXPIRE_DAYS = settings.REFRESH_TOKEN_EXPIRE_DAYS
TOTP_PENDING_EXPIRE_MINUTES = 5

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

router = APIRouter()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

redis_client = redis_lib.Redis(
    host=settings.REDIS_HOST,
    port=settings.REDIS_PORT,
    db=settings.REDIS_DB,
    decode_responses=True
)

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def authenticate_user(username: str, password: str):
    user_pw = sqloader.fetch_one("chorus", "get_password", (username,))
    if not user_pw or not verify_password(password, user_pw.get("password", "")):
        return False
    result = sqloader.fetch_one("chorus", "get_user", (username,))
    logger.debug(result)
    return result


def create_access_token(data: dict, expires_delta: timedelta):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + expires_delta
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


_MAINTENANCE_DIR = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "res", "maintenance")
)
_MAINTENANCE_SUPPORTED_LANGS = {"en", "ko", "ja"}


def _get_maintenance_message(locale: str) -> str:
    """Returns the maintenance message for the given locale. Falls back to en for unsupported locales.
    Also handles region-code variants like ko_KR and en_US by extracting the first 2 characters."""
    lang_code = (locale or "en")[:2].lower()
    lang = lang_code if lang_code in _MAINTENANCE_SUPPORTED_LANGS else "en"
    path = os.path.join(_MAINTENANCE_DIR, f"maintenance_{lang}.txt")
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception as e:
        logger.error(f"[Maintenance] failed to load message file: {path} — {e}")
        return "Server maintenance in progress."


class LoginRequest(BaseModel):
    username: EmailStr  # email address
    password: str
    locale: str = "en"  # REL-010: client locale — falls back to en if not provided


class TotpVerifyRequest(BaseModel):
    temp_token: str
    code: str


class RefreshTokenRequest(BaseModel):
    refresh_token: str


@router.post("/")
@router.post("")
@limiter.limit(settings.RATE_LIMIT_LOGIN)
async def login(request: Request, body: LoginRequest):
    # REL-010: maintenance mode — block before auth attempt, return maintenance message
    if settings.MAINTENANCE_MODE:
        message = _get_maintenance_message(body.locale)
        logger.debug(f"[Login] maintenance mode — login blocked, locale={body.locale}")
        return {"maintenance": True, "message": message}

    user = authenticate_user(body.username, body.password)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid credentials")

    if not user.get("email_verified", False):
        raise HTTPException(status_code=403, detail="email_not_verified")

    user_id = user["user_id"]

    # Check TOTP 2FA (skip if tfa is None)
    totp_enabled = False
    if tfa is not None:
        totp_enabled = tfa.is_enabled(user_id)
        logger.debug(f"[Login] user_id: {user_id}, TOTP enabled: {totp_enabled}")

        if totp_enabled:
            temp_token = create_access_token(
                data={"sub": user_id, "totp_pending": True},
                expires_delta=timedelta(minutes=TOTP_PENDING_EXPIRE_MINUTES),
            )
            logger.debug(f"[Login] temp_token issued - user_id: {user_id}")
            return {"totp_required": True, "temp_token": temp_token}

    access_token = create_access_token(
        data={"sub": user_id},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    refresh_token = create_access_token(
        data={"sub": user_id, "type": "refresh"},
        expires_delta=timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS),
    )
    redis_client.setex(
        f"refresh:{user_id}",
        REFRESH_TOKEN_EXPIRE_DAYS * 86400,
        refresh_token,
    )
    logger.debug({"access_token": access_token, "token_type": "bearer", "user": user})
    return {"access_token": access_token, "refresh_token": refresh_token, "token_type": "bearer", "user": user}


@router.post("/totp/verify")
async def verify_totp_login(request: Request, body: TotpVerifyRequest):
    logger.debug(f"[TOTP Verify] request received - temp_token: {body.temp_token[:50]}..., code: {body.code}")

    credentials_exception = HTTPException(
        status_code=401,
        detail="token_expired",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = jwt.decode(body.temp_token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": True})
        logger.debug(f"[TOTP Verify] JWT parsed - payload: {payload}")
    except jwt.ExpiredSignatureError:
        logger.debug("[TOTP Verify] ❌ JWT expired (ExpiredSignatureError)")
        raise HTTPException(status_code=401, detail="token_expired")
    except jwt.InvalidTokenError as e:
        logger.debug(f"[TOTP Verify] ❌ JWT parse failed (InvalidTokenError): {e}")
        raise credentials_exception

    user_id = payload.get("sub")
    totp_pending = payload.get("totp_pending", False)
    logger.debug(f"[TOTP Verify] extracted user_id: {user_id}, totp_pending: {totp_pending}")

    if not user_id or not totp_pending:
        logger.debug(f"[TOTP Verify] ❌ user_id or totp_pending missing")
        raise credentials_exception

    logger.debug(f"[TOTP Verify] calling tfa.verify - user_id: {user_id}, code: {body.code}")
    verify_result = tfa.verify(user_id, body.code)
    logger.debug(f"[TOTP Verify] tfa.verify result: {verify_result}")

    if not verify_result:
        logger.debug(f"[TOTP Verify] ❌ TOTP verification failed - user_id: {user_id}, code: {body.code}")
        raise HTTPException(status_code=401, detail="invalid_code")

    user = sqloader.fetch_one("chorus", "get_user", (user_id,))
    access_token = create_access_token(
        data={"sub": user_id},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    logger.debug(f"[TOTP Verify] ✅ login succeeded - user_id: {user_id}")
    return {"access_token": access_token, "token_type": "bearer", "user": user}


@router.post("/token/refresh")
async def token_refresh(body: RefreshTokenRequest):
    invalid_exc = HTTPException(
        status_code=401,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    expired_exc = HTTPException(
        status_code=401,
        detail="Token has expired",
        headers={"WWW-Authenticate": "Bearer"},
    )

    received_token = body.refresh_token

    # Step 2: Decode without verification to extract user_id
    try:
        unverified_payload = jwt.decode(
            received_token,
            options={"verify_signature": False},
            algorithms=[ALGORITHM],
        )
        user_id = unverified_payload.get("sub")
        if not user_id:
            raise invalid_exc
    except jwt.InvalidTokenError:
        raise invalid_exc

    # Step 3-4: Check Redis and compare stored token
    stored_token = redis_client.get(f"refresh:{user_id}")
    if stored_token is None:
        raise invalid_exc
    if stored_token != received_token:
        raise invalid_exc

    # Step 5: Verify JWT signature and expiry
    try:
        payload = jwt.decode(
            received_token,
            SECRET_KEY,
            algorithms=[ALGORITHM],
            options={"verify_exp": True},
        )
    except jwt.ExpiredSignatureError:
        raise expired_exc
    except jwt.InvalidTokenError:
        raise invalid_exc

    # Step 6: Check type == "refresh"
    if payload.get("type") != "refresh":
        raise invalid_exc

    # Step 7: Create new access_token
    new_access_token = create_access_token(
        data={"sub": user_id},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )

    # Steps 8-10: Rotate refresh_token with inherited exp
    original_exp: int = payload["exp"]
    now_ts = int(datetime.now(timezone.utc).timestamp())
    remaining_ttl = original_exp - now_ts
    if remaining_ttl <= 0:
        raise expired_exc

    original_exp_dt = datetime.fromtimestamp(original_exp, tz=timezone.utc)
    remaining_delta = original_exp_dt - datetime.now(timezone.utc)

    redis_client.delete(f"refresh:{user_id}")

    new_refresh_token = create_access_token(
        data={"sub": user_id, "type": "refresh"},
        expires_delta=remaining_delta,
    )
    redis_client.setex(f"refresh:{user_id}", remaining_ttl, new_refresh_token)

    return {
        "access_token": new_access_token,
        "refresh_token": new_refresh_token,
        "token_type": "bearer",
    }
