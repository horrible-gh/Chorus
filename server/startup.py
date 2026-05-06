"""서버 초기화 헬퍼 — main.py 에서 분리된 부트스트랩 로직."""
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
    """백그라운드 폴링 루프를 asyncio 태스크로 등록한다."""
    global _poll_task
    from modules.worker_loop import poll_loop
    _poll_task = asyncio.create_task(poll_loop())
    logger.info("[startup] poll_loop 태스크 등록 완료")


async def stop_poll_loop() -> None:
    """폴링 루프를 graceful하게 중단한다."""
    global _poll_task
    if _poll_task and not _poll_task.done():
        _poll_task.cancel()
        try:
            await _poll_task
        except asyncio.CancelledError:
            pass
        logger.info("[startup] poll_loop 태스크 종료 완료")
