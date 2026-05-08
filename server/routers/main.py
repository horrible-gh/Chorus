from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from .login import login, logout, register, verify_mail, privacy_policy
from .chat import chat
from .agent import agent
from .routing import routing
from .worker import worker
from .model import model as model_module
from . import settings as settings_module
from .auth import cli_auth as cli_auth_module
from .auth import provider_management as provider_management_module
from . import token as token_module
from . import files as files_module
from . import ws as ws_module
from routers.login.auth import verify_token
from config import settings
from startup import run_all as _bootstrap, start_poll_loop, stop_poll_loop
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
    """Lifespan handler executed on server startup and shutdown."""
    _bootstrap()          # console encoding + PercentileTable pre-build
    await start_poll_loop()
    yield                  # ← server running
    await stop_poll_loop()


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
app.include_router(ws_module.router, prefix=f"{CONTEXT}/ws", tags=["ChorusWS"])
app.include_router(model_module.router, prefix=f"{CONTEXT}/models", tags=["ChorusModels"])
app.include_router(cli_auth_module.router, prefix=f"{CONTEXT}/auth", tags=["ChorusAuth"])
app.include_router(provider_management_module.router, prefix=f"{CONTEXT}/auth", tags=["ChorusProviders"])
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
    logger.debug(f"🔍 Request Headers: {request.headers}")  # ✅ print all headers
    return {"headers": dict(request.headers)}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.debug("💥 Validation error occurred")
    logger.debug("⛳ Path:", request.url)
    logger.debug("📦 Body:\n", exc.errors())
    logger.debug("📨 Raw body:\n", await request.body())
