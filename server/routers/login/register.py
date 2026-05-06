from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, EmailStr
from passlib.context import CryptContext
import random
import string
from config import settings, db
from slowapi import Limiter
from slowapi.util import get_remote_address
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

limiter = Limiter(key_func=get_remote_address)
pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

router = APIRouter()


class RegisterRequest(BaseModel):
    user_id: EmailStr  # email address
    password: str


class RegisterResponse(BaseModel):
    user_id: str
    email_verified: bool
    verify_code: str  # included in response only during development (email in production)


def generate_verify_code(length: int = 6) -> str:
    """Generate a 6-digit numeric verification code"""
    return ''.join(random.choices(string.digits, k=length))


def hash_password(password: str) -> str:
    """Hash a password"""
    return pwd_context.hash(password)


@router.post("/", response_model=RegisterResponse)
@router.post("", response_model=RegisterResponse)
@limiter.limit(settings.RATE_LIMIT_LOGIN)
async def register(request: Request, body: RegisterRequest):
    """
    User registration API
    - user_id: email address
    - password: password
    - Check duplicate → hash password → create user → generate verification code
    """
    user_id = body.user_id
    password = body.password

    logger.debug(f"[Register] registration request - user_id: {user_id}")

    # 1. Check for duplicate
    duplicate_check = sqloader.fetch_one("chorus", "check_duplicate_user", (user_id,))
    if duplicate_check and duplicate_check.get("count", 0) > 0:
        logger.debug(f"[Register] ❌ duplicate email - user_id: {user_id}")
        raise HTTPException(status_code=400, detail="Email already registered")

    # 2. Hash password
    hashed_password = hash_password(password)

    # 3. Begin transaction
    try:
        db_instance.begin_transaction()

        # 4. Create user
        sqloader.execute("chorus", "create_user", (user_id, hashed_password))

        # 5. Create player data (initial chips: 50,000)
        sqloader.execute("chorus", "create_player_data", (user_id,))

        # 6. Generate and store verification code
        verify_code = generate_verify_code(6)
        sqloader.execute("chorus", "save_verify_code", (user_id, verify_code))

        # 7. Commit transaction
        db_instance.commit()

        logger.debug(f"[Register] ✅ registration complete - user_id: {user_id}, verify_code: {verify_code}")

        # TODO: add email sending logic in production
        # send_verification_email(user_id, verify_code)

        return RegisterResponse(
            user_id=user_id,
            email_verified=False,
            verify_code=verify_code  # included only during development
        )

    except Exception as e:
        # Rollback on error
        try:
            db_instance.rollback()
        except:
            pass
        logger.error(f"[Register] ❌ registration failed - {e}")
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")
