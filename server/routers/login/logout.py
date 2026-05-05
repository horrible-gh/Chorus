from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from passlib.context import CryptContext
import jwt
from datetime import datetime, timedelta, timezone
from config import settings, db
import redis

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

# OAuth2 방식으로 토큰 받기
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

# JWT Secret Key (실제 서비스에서는 환경변수 사용 권장)
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES


redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)

@router.post("/")
async def logout(token: str = Depends(oauth2_scheme)):
    """ 현재 사용 중인 JWT 토큰을 블랙리스트에 등록 (로그아웃) """
    exp_time = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])["exp"]
    remaining_time = exp_time - datetime.now(timezone.utc).timestamp()

    # ✅ Redis에 토큰을 저장하고 만료 시간까지 유지
    redis_client.setex(f"blacklist:{token}", int(remaining_time), "1")

    return {"message": "Logged out successfully"}
