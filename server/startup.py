"""서버 초기화 헬퍼 — main.py 에서 분리된 부트스트랩 로직."""
import sys
import io
import time
import LogAssist.log as logger


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
