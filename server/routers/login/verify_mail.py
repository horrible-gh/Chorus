from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, EmailStr
from config import settings, db
from slowapi import Limiter
from slowapi.util import get_remote_address
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

limiter = Limiter(key_func=get_remote_address)

router = APIRouter()


class VerifyMailRequest(BaseModel):
    user_id: EmailStr  # 이메일 주소
    verify_code: str   # 6자리 인증 코드


class VerifyMailResponse(BaseModel):
    user_id: str
    email_verified: bool
    message: str


@router.post("/", response_model=VerifyMailResponse)
@router.post("", response_model=VerifyMailResponse)
@limiter.limit(settings.RATE_LIMIT_LOGIN)
async def verify_mail(request: Request, body: VerifyMailRequest):
    """
    이메일 인증 API
    - user_id: 이메일 주소
    - verify_code: 6자리 인증 코드
    - 인증 코드 확인 → 이메일 인증 완료 처리
    """
    user_id = body.user_id
    verify_code = body.verify_code

    logger.debug(f"[VerifyMail] 이메일 인증 요청 - user_id: {user_id}, code: {verify_code}")

    # 1. 인증 코드 확인 (유효성 검증)
    verification = sqloader.fetch_one("chipsama", "check_verify_code", (user_id, verify_code))

    if not verification:
        logger.debug(f"[VerifyMail] ❌ 인증 코드 불일치 또는 만료 - user_id: {user_id}")
        raise HTTPException(status_code=400, detail="Invalid or expired verification code")

    verification_id = verification.get("id")
    logger.debug(f"[VerifyMail] ✅ 인증 코드 확인 완료 - verification_id: {verification_id}")

    # 2. 트랜잭션으로 이메일 인증 처리
    try:
        db_instance.begin_transaction()

        # 이메일 인증 완료 처리
        sqloader.execute("chipsama", "update_email_verified", (user_id,))

        # 인증 코드 사용 처리 (재사용 방지)
        sqloader.execute("chipsama", "mark_verify_code_used", (verification_id,))

        db_instance.commit()
        logger.debug(f"[VerifyMail] ✅ 이메일 인증 완료 - user_id: {user_id}")

    except Exception as e:
        try:
            db_instance.rollback()
        except:
            pass
        logger.error(f"[VerifyMail] ❌ 이메일 인증 실패 - {e}")
        raise HTTPException(status_code=500, detail="Email verification failed")

    return VerifyMailResponse(
        user_id=user_id,
        email_verified=True,
        message="Email verified successfully"
    )
