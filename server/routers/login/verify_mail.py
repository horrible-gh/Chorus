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
    user_id: EmailStr  # email address
    verify_code: str   # 6-digit verification code


class VerifyMailResponse(BaseModel):
    user_id: str
    email_verified: bool
    message: str


@router.post("/", response_model=VerifyMailResponse)
@router.post("", response_model=VerifyMailResponse)
@limiter.limit(settings.RATE_LIMIT_LOGIN)
async def verify_mail(request: Request, body: VerifyMailRequest):
    """
    Email verification API
    - user_id: email address
    - verify_code: 6-digit verification code
    - Validates code → marks email as verified
    """
    user_id = body.user_id
    verify_code = body.verify_code

    logger.debug(f"[VerifyMail] email verification request - user_id: {user_id}, code: {verify_code}")

    # 1. Check verification code (validate)
    verification = sqloader.fetch_one("chipsama", "check_verify_code", (user_id, verify_code))

    if not verification:
        logger.debug(f"[VerifyMail] ❌ code mismatch or expired - user_id: {user_id}")
        raise HTTPException(status_code=400, detail="Invalid or expired verification code")

    verification_id = verification.get("id")
    logger.debug(f"[VerifyMail] ✅ code verified - verification_id: {verification_id}")

    # 2. Process email verification in a transaction
    try:
        db_instance.begin_transaction()

        # Mark email as verified
        sqloader.execute("chipsama", "update_email_verified", (user_id,))

        # Mark verification code as used (prevent reuse)
        sqloader.execute("chipsama", "mark_verify_code_used", (verification_id,))

        db_instance.commit()
        logger.debug(f"[VerifyMail] ✅ email verified - user_id: {user_id}")

    except Exception as e:
        try:
            db_instance.rollback()
        except:
            pass
        logger.error(f"[VerifyMail] ❌ email verification failed - {e}")
        raise HTTPException(status_code=500, detail="Email verification failed")

    return VerifyMailResponse(
        user_id=user_id,
        email_verified=True,
        message="Email verified successfully"
    )
