import jwt
from datetime import datetime, timezone
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from config import settings
import redis

import LogAssist.log as Logger

# JWT configuration
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

# Redis client for blacklist verification
redis_client = redis.Redis(
    host=settings.REDIS_HOST,
    port=settings.REDIS_PORT,
    db=settings.REDIS_DB,
    decode_responses=True
)

def is_token_blacklisted(token: str) -> bool:
    """ Check if the token is on the blacklist in Redis """
    return redis_client.exists(f"blacklist:{token}") > 0

def verify_token(token: str = Depends(oauth2_scheme)):
    #Logger.debug(f"🔍 Received token: {token}")

    credentials_exception = HTTPException(
        status_code=401,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        # ✅ Check if token is blacklisted
        if is_token_blacklisted(token):
            raise HTTPException(status_code=401, detail="Token has been logged out")

        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": True})
        user_id: str = payload.get("sub")
        exp: int = payload.get("exp")
        totp_pending: bool = payload.get("totp_pending", False)

        if payload.get("type") == "refresh":
            raise HTTPException(status_code=401, detail="Invalid authentication credentials")

        if user_id is None or exp is None:
            raise credentials_exception

        # totp_pending token cannot access regular API endpoints
        if totp_pending:
            raise HTTPException(status_code=401, detail="2FA verification required")

        if datetime.now(timezone.utc) > datetime.fromtimestamp(exp, timezone.utc):
            raise HTTPException(status_code=401, detail="Token has expired")

        return user_id

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError:
        raise credentials_exception

