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
    user_id: EmailStr  # 이메일 주소
    password: str


class RegisterResponse(BaseModel):
    user_id: str
    email_verified: bool
    verify_code: str  # 개발 단계에서만 응답에 포함 (실제로는 이메일 전송)


def generate_verify_code(length: int = 6) -> str:
    """6자리 숫자 인증 코드 생성"""
    return ''.join(random.choices(string.digits, k=length))


def hash_password(password: str) -> str:
    """비밀번호 해싱"""
    return pwd_context.hash(password)


@router.post("/", response_model=RegisterResponse)
@router.post("", response_model=RegisterResponse)
@limiter.limit(settings.RATE_LIMIT_LOGIN)
async def register(request: Request, body: RegisterRequest):
    """
    회원가입 API
    - user_id: 이메일 주소
    - password: 비밀번호
    - 중복 확인 → 비밀번호 해싱 → 사용자 생성 → 인증 코드 생성
    """
    user_id = body.user_id
    password = body.password

    logger.debug(f"[Register] 회원가입 요청 - user_id: {user_id}")

    # 1. 중복 확인
    duplicate_check = sqloader.fetch_one("chorus", "check_duplicate_user", (user_id,))
    if duplicate_check and duplicate_check.get("count", 0) > 0:
        logger.debug(f"[Register] ❌ 중복된 이메일 - user_id: {user_id}")
        raise HTTPException(status_code=400, detail="Email already registered")

    # 2. 비밀번호 해싱
    hashed_password = hash_password(password)

    # 3. 트랜잭션 시작
    try:
        db_instance.begin_transaction()

        # 4. 사용자 생성
        sqloader.execute("chorus", "create_user", (user_id, hashed_password))

        # 5. 플레이어 데이터 생성 (초기 칩 50,000)
        sqloader.execute("chorus", "create_player_data", (user_id,))

        # 6. 인증 코드 생성 및 저장
        verify_code = generate_verify_code(6)
        sqloader.execute("chorus", "save_verify_code", (user_id, verify_code))

        # 7. 트랜잭션 커밋
        db_instance.commit()

        logger.debug(f"[Register] ✅ 회원가입 완료 - user_id: {user_id}, verify_code: {verify_code}")

        # TODO: 실제 서비스에서는 이메일 전송 로직 추가
        # send_verification_email(user_id, verify_code)

        return RegisterResponse(
            user_id=user_id,
            email_verified=False,
            verify_code=verify_code  # 개발 단계에서만 포함
        )

    except Exception as e:
        # 에러 발생 시 롤백
        try:
            db_instance.rollback()
        except:
            pass
        logger.error(f"[Register] ❌ 회원가입 실패 - {e}")
        raise HTTPException(status_code=500, detail=f"Registration failed: {str(e)}")
