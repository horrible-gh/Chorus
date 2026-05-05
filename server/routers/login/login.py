from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr
import jwt
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
TOTP_PENDING_EXPIRE_MINUTES = 5

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

router = APIRouter()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

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
    """locale 기준 완성 유지보수 메시지 반환. 미지원 locale은 en fallback.
    ko_KR, en_US 등 지역 코드 포함 형태도 앞 2자리만 추출해 처리한다."""
    lang_code = (locale or "en")[:2].lower()
    lang = lang_code if lang_code in _MAINTENANCE_SUPPORTED_LANGS else "en"
    path = os.path.join(_MAINTENANCE_DIR, f"maintenance_{lang}.txt")
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except Exception as e:
        logger.error(f"[Maintenance] 메시지 파일 로드 실패: {path} — {e}")
        return "Server maintenance in progress."


class LoginRequest(BaseModel):
    username: EmailStr  # 이메일 주소
    password: str
    locale: str = "en"  # REL-010: 클라 locale 수신 — 미전달 시 en fallback


class TotpVerifyRequest(BaseModel):
    temp_token: str
    code: str


@router.post("/")
@router.post("")
@limiter.limit(settings.RATE_LIMIT_LOGIN)
async def login(request: Request, body: LoginRequest):
    # REL-010: maintenance mode — 인증 시도 전 차단, 완성 메시지 반환
    if settings.MAINTENANCE_MODE:
        message = _get_maintenance_message(body.locale)
        logger.debug(f"[Login] maintenance mode — 로그인 차단, locale={body.locale}")
        return {"maintenance": True, "message": message}

    user = authenticate_user(body.username, body.password)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid credentials")

    if not user.get("email_verified", False):
        raise HTTPException(status_code=403, detail="email_not_verified")

    user_id = user["user_id"]

    # TOTP 2FA 확인 (tfa가 None이면 건너뛰기)
    totp_enabled = False
    if tfa is not None:
        totp_enabled = tfa.is_enabled(user_id)
        logger.debug(f"[Login] user_id: {user_id}, TOTP 활성화 여부: {totp_enabled}")

        if totp_enabled:
            temp_token = create_access_token(
                data={"sub": user_id, "totp_pending": True},
                expires_delta=timedelta(minutes=TOTP_PENDING_EXPIRE_MINUTES),
            )
            logger.debug(f"[Login] temp_token 발급 - user_id: {user_id}")
            return {"totp_required": True, "temp_token": temp_token}

    access_token = create_access_token(
        data={"sub": user_id},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    logger.debug({"access_token": access_token, "token_type": "bearer", "user": user})
    return {"access_token": access_token, "token_type": "bearer", "user": user}


@router.post("/totp/verify")
async def verify_totp_login(request: Request, body: TotpVerifyRequest):
    logger.debug(f"[TOTP Verify] 요청 받음 - temp_token: {body.temp_token[:50]}..., code: {body.code}")

    credentials_exception = HTTPException(
        status_code=401,
        detail="token_expired",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        payload = jwt.decode(body.temp_token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": True})
        logger.debug(f"[TOTP Verify] JWT 파싱 성공 - payload: {payload}")
    except jwt.ExpiredSignatureError:
        logger.debug("[TOTP Verify] ❌ JWT 만료됨 (ExpiredSignatureError)")
        raise HTTPException(status_code=401, detail="token_expired")
    except jwt.InvalidTokenError as e:
        logger.debug(f"[TOTP Verify] ❌ JWT 파싱 실패 (InvalidTokenError): {e}")
        raise credentials_exception

    user_id = payload.get("sub")
    totp_pending = payload.get("totp_pending", False)
    logger.debug(f"[TOTP Verify] 추출된 user_id: {user_id}, totp_pending: {totp_pending}")

    if not user_id or not totp_pending:
        logger.debug(f"[TOTP Verify] ❌ user_id 또는 totp_pending 없음")
        raise credentials_exception

    logger.debug(f"[TOTP Verify] tfa.verify 호출 - user_id: {user_id}, code: {body.code}")
    verify_result = tfa.verify(user_id, body.code)
    logger.debug(f"[TOTP Verify] tfa.verify 결과: {verify_result}")

    if not verify_result:
        logger.debug(f"[TOTP Verify] ❌ TOTP 검증 실패 - user_id: {user_id}, code: {body.code}")
        raise HTTPException(status_code=401, detail="invalid_code")

    user = sqloader.fetch_one("chorus", "get_user", (user_id,))
    access_token = create_access_token(
        data={"sub": user_id},
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    logger.debug(f"[TOTP Verify] ✅ 로그인 성공 - user_id: {user_id}")
    return {"access_token": access_token, "token_type": "bearer", "user": user}
