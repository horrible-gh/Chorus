from fastapi import APIRouter, Depends, HTTPException

from config import settings, db, tfa
from routers.login.auth import verify_token
from passlib.context import CryptContext
from schemas.settings import (
    ChangePasswordRequest,
    TotpActivateRequest,
    TotpActivateResponse,
    TotpDisableRequest,
    TotpSetupResponse,
    UserProfileResponse,
)
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

router = APIRouter()


# ── 프로필 조회 ─────────────────────────────────────────────────────
@router.get("/profile", response_model=UserProfileResponse)
async def get_profile(user_id: str = Depends(verify_token)):
    user = sqloader.fetch_one("chorus", "get_user", (user_id,))
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    totp_enabled = tfa.is_enabled(user_id) if tfa is not None else False

    return UserProfileResponse(
        user_id=user["user_id"],
        email_verified=bool(user.get("email_verified", False)),
        totp_enabled=totp_enabled,
    )


# ── 비밀번호 변경 ─────────────────────────────────────────────────────
@router.put("/password")
async def change_password(
    body: ChangePasswordRequest,
    user_id: str = Depends(verify_token),
):
    row = sqloader.fetch_one("chorus", "get_password", (user_id,))
    if not row:
        raise HTTPException(status_code=404, detail="User not found")

    if not pwd_context.verify(body.current_password, row["password"]):
        raise HTTPException(status_code=400, detail="current_password_incorrect")

    if body.current_password == body.new_password:
        raise HTTPException(status_code=400, detail="new_password_same_as_current")

    hashed = pwd_context.hash(body.new_password)
    sqloader.execute("chorus", "update_password", (hashed, user_id))
    logger.debug(f"[Settings] 비밀번호 변경 완료 - user_id: {user_id}")
    return {"ok": True}


# ── TOTP 설정 초기화 ─────────────────────────────────────────────────
@router.post("/totp/setup", response_model=TotpSetupResponse)
async def setup_totp(user_id: str = Depends(verify_token)):
    if tfa is None:
        raise HTTPException(status_code=503, detail="2FA service unavailable")

    if tfa.is_enabled(user_id):
        raise HTTPException(status_code=400, detail="totp_already_enabled")

    try:
        result = tfa.setup(user_id, username=user_id)
    except ValueError as exc:
        # TOTP already configured but not activated — remove and re-setup
        tfa.disable(user_id)
        result = tfa.setup(user_id, username=user_id)

    logger.debug(f"[Settings] TOTP 설정 초기화 - user_id: {user_id}")
    return TotpSetupResponse(**result)


# ── TOTP 활성화 ─────────────────────────────────────────────────────
@router.post("/totp/activate", response_model=TotpActivateResponse)
async def activate_totp(
    body: TotpActivateRequest,
    user_id: str = Depends(verify_token),
):
    if tfa is None:
        raise HTTPException(status_code=503, detail="2FA service unavailable")

    if tfa.is_enabled(user_id):
        raise HTTPException(status_code=400, detail="totp_already_enabled")

    try:
        ok = tfa.activate(user_id, body.code)
    except ValueError:
        raise HTTPException(status_code=400, detail="totp_not_configured")

    if not ok:
        raise HTTPException(status_code=400, detail="invalid_totp_code")

    logger.debug(f"[Settings] TOTP 활성화 완료 - user_id: {user_id}")
    return TotpActivateResponse(ok=True)


# ── TOTP 비활성화 ─────────────────────────────────────────────────────
@router.delete("/totp", response_model=dict)
async def disable_totp(
    body: TotpDisableRequest,
    user_id: str = Depends(verify_token),
):
    if tfa is None:
        raise HTTPException(status_code=503, detail="2FA service unavailable")

    if not tfa.is_enabled(user_id):
        raise HTTPException(status_code=400, detail="totp_not_enabled")

    if not tfa.verify(user_id, body.code):
        raise HTTPException(status_code=400, detail="invalid_totp_code")

    tfa.disable(user_id)
    logger.debug(f"[Settings] TOTP 비활성화 완료 - user_id: {user_id}")
    return {"ok": True}
