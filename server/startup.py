"""Server initialization helper — bootstrap logic extracted from main.py."""
import asyncio
import sys
import io
import time
import LogAssist.log as logger

_poll_task: asyncio.Task = None


def configure_console_encoding():
    """Force Windows console encoding to UTF-8."""
    if sys.platform == "win32":
        sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
        sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8")


def preload_singletons():
    """Pre-build heavy singletons to prevent delays at runtime.
    """
    pass


def run_all():
    """Run full bootstrap sequence (called at lifespan entry)."""
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
