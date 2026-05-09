from fastapi import APIRouter, Depends, HTTPException, Body
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from passlib.context import CryptContext
from pydantic import BaseModel
from typing import Optional
import jwt
from datetime import datetime, timedelta, timezone
from config import settings, db
import redis

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

# Receive token via OAuth2
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

# JWT Secret Key (use environment variables in production)
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES


redis_client = redis.Redis(
    host=settings.REDIS_HOST,
    port=settings.REDIS_PORT,
    db=settings.REDIS_DB,
    decode_responses=True
)


class LogoutRequest(BaseModel):
    refresh_token: Optional[str] = None


@router.post("/")
async def logout(token: str = Depends(oauth2_scheme), body: Optional[LogoutRequest] = Body(None)):
    """ Add the current JWT token to the blacklist (logout) and revoke refresh token """
    decoded = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    exp_time = decoded["exp"]
    user_id = decoded.get("sub")
    remaining_time = exp_time - datetime.now(timezone.utc).timestamp()

    # ✅ Store access_token in Redis blacklist until expiry
    redis_client.setex(f"blacklist:{token}", int(remaining_time), "1")

    # ✅ Delete refresh token from Redis (always, regardless of body)
    if user_id:
        redis_client.delete(f"refresh:{user_id}")

    return {"message": "Logged out successfully"}
