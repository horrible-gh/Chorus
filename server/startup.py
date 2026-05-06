"""Server initialization helper — bootstrap logic extracted from main.py."""
import asyncio
import sys
import io
import time
import LogAssist.log as logger

_poll_task: asyncio.Task = None


def configure_console_encoding():
    """Windows 콘솔 인코딩 강제 UTF-8."""
    if sys.platform == "win32":
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8")


def preload_singletons():
    """무거운 싱글턴 미리 빌드 — 게임 중 딜레이 방지.
    """
    pass


def run_all():
    """부트스트랩 전체 실행 (lifespan 진입 시 호출)."""
    configure_console_encoding()
    preload_singletons()


async def start_poll_loop() -> None:
    """Registers the background polling loop as an asyncio task."""
    global _poll_task
    from modules.worker_loop import poll_loop, _POLL_WORKER_ID
    from modules.chat_manager import STORE
    STORE.delete_leases_by_worker(_POLL_WORKER_ID)
    logger.info(f"[startup] stale lease cleanup done — worker_id={_POLL_WORKER_ID!r}")
    _poll_task = asyncio.create_task(poll_loop())
    logger.info("[startup] poll_loop task registered")


async def stop_poll_loop() -> None:
    """Gracefully stops the polling loop."""
    global _poll_task
    if _poll_task and not _poll_task.done():
        _poll_task.cancel()
        try:
            await _poll_task
        except asyncio.CancelledError:
            pass
        logger.info("[startup] poll_loop task stopped")
