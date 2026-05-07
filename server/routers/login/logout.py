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

@router.post("/")
async def logout(token: str = Depends(oauth2_scheme)):
    """ Add the current JWT token to the blacklist (logout) """
    exp_time = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])["exp"]
    remaining_time = exp_time - datetime.now(timezone.utc).timestamp()

    # ✅ Store token in Redis and retain until expiry
    redis_client.setex(f"blacklist:{token}", int(remaining_time), "1")

    return {"message": "Logged out successfully"}
