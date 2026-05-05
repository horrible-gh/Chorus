from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from .login import login, logout, register, verify_mail, privacy_policy
from .chat import chat
from .agent import agent
from .routing import routing
from .worker import worker
from . import settings as settings_module
from . import token as token_module
from . import files as files_module
from routers.login.auth import verify_token, token_blacklist
from config import settings
from startup import run_all as _bootstrap
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
import LogAssist.log as logger

ALLOWED_ORIGIN = settings.ALLOWED_ORIGIN.split(",")
CONTEXT = settings.CONTEXT

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[settings.RATE_LIMIT_DEFAULT]
)


# ── Lifespan ─────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """서버 시작/종료 시 실행되는 lifespan 핸들러."""
    _bootstrap()          # 콘솔 인코딩 + PercentileTable 프리빌드
    yield                  # ← 서버 가동 중
    # shutdown 로직 필요 시 여기에 추가


app = FastAPI(lifespan=lifespan)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

app.include_router(login.router, prefix=f"{CONTEXT}/login", tags=["Login"])
app.include_router(logout.router, prefix=f"{CONTEXT}/logout", tags=["Logout"])
app.include_router(register.router, prefix=f"{CONTEXT}/register", tags=["Register"])
app.include_router(verify_mail.router, prefix=f"{CONTEXT}/verify_mail", tags=["VerifyMail"])
app.include_router(privacy_policy.router, prefix=f"{CONTEXT}/privacy_policy", tags=["PrivacyPolicy"])
app.include_router(chat.router, prefix=f"{CONTEXT}/chat", tags=["ChorusChat"])
app.include_router(agent.router, prefix=f"{CONTEXT}/agent", tags=["ChorusAgent"])
app.include_router(routing.router, prefix=f"{CONTEXT}/routing", tags=["ChorusRouting"])
app.include_router(worker.router, prefix=f"{CONTEXT}/worker", tags=["ChorusWorker"])
app.include_router(settings_module.router, prefix=f"{CONTEXT}/settings", tags=["ChorusSettings"])
app.include_router(token_module.router, prefix=f"{CONTEXT}/tokens", tags=["ChorusTokens"])
app.include_router(files_module.router, prefix=f"{CONTEXT}/files", tags=["ChorusFiles"])
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGIN,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition"],
)


@app.get(CONTEXT + "/")
async def read_root():
    return {"message": "Hello FastAPI"}

@app.get(CONTEXT + "/items/{item_id}")
async def read_item(item_id: int, q: str = None):
    return {"item_id": item_id, "query": q}


@app.get(CONTEXT + "/debug-headers")
async def debug_headers(request: Request):
    logger.debug(f"🔍 Request Headers: {request.headers}")  # ✅ 모든 헤더 출력
    return {"headers": dict(request.headers)}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.debug("💥 Validation error 발생")
    logger.debug("⛳ 경로:", request.url)
    logger.debug("📦 내용:\n", exc.errors())
    logger.debug("📨 원본 body:\n", await request.body())
