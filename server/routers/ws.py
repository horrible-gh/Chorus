"""WebSocket router — per room_id event subscription endpoint."""
from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone, timedelta

import jwt
from fastapi import APIRouter, Header, Query, WebSocket, WebSocketDisconnect

from config import settings
from modules.push_manager import push_manager
from routers.login.auth import token_blacklist

import LogAssist.log as logger

JST = timezone(timedelta(hours=9))
HEARTBEAT_INTERVAL = 30  # seconds

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"

router = APIRouter()


def _verify_ws_token(authorization: str | None) -> str | None:
    """Verify a WebSocket auth token and return user_id. Returns None on failure."""
    if not authorization or not authorization.startswith("Bearer "):
        return None
    token = authorization[len("Bearer "):]
    if token in token_blacklist:
        return None
    try:
        payload = jwt.decode(
            token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": True}
        )
        user_id: str | None = payload.get("sub")
        if not user_id:
            return None
        if payload.get("totp_pending", False):
            return None
        return user_id
    except jwt.PyJWTError:
        return None


def _now_iso() -> str:
    return datetime.now(JST).isoformat(timespec="seconds")


@router.websocket("/rooms/{room_id}/events")
async def ws_room_events(
    websocket: WebSocket,
    room_id: str,
    authorization: str | None = Header(default=None),
    access_token: str | None = Query(default=None),
) -> None:
    """Per room_id WebSocket subscription endpoint.

    Auth order: Authorization header first, then ?access_token query param (for Flutter Web).
    Sends subscribe_success event on connect, and heartbeat every 30 seconds.
    """
    # Authorization header first, fall back to query param (Flutter Web)
    if authorization:
        auth_value = authorization
    elif access_token:
        auth_value = f"Bearer {access_token}"
    else:
        auth_value = None

    user_id = _verify_ws_token(auth_value)
    if user_id is None:
        logger.info(
            f"[ws_room_events] auth failed room_id={room_id!r} "
            f"has_header={authorization is not None} "
            f"has_query_token={access_token is not None}"
        )
        await websocket.accept()
        await websocket.send_text(
            json.dumps(
                {
                    "type": "error",
                    "error_code": "AUTH_FAILED",
                    "message": "Authentication failed. Please check your token.",
                    "retry_after": -1,
                },
                ensure_ascii=False,
            )
        )
        await websocket.close(code=4001)
        return

    await websocket.accept()
    await push_manager.connect(room_id, websocket)
    subscriber_count = push_manager.subscriber_count(room_id)
    logger.info(
        f"[ws_room_events] registered user_id={user_id!r} room_id={room_id!r} "
        f"auth_method={'header' if authorization else 'query_token'} "
        f"subscribers={subscriber_count}"
    )

    try:
        await websocket.send_text(
            json.dumps(
                {
                    "type": "subscribe_success",
                    "room_id": room_id,
                    "server_time": _now_iso(),
                },
                ensure_ascii=False,
            )
        )

        while True:
            try:
                await asyncio.wait_for(
                    websocket.receive_text(), timeout=float(HEARTBEAT_INTERVAL)
                )
                # Phase 1: ignore client messages.
            except asyncio.TimeoutError:
                try:
                    await websocket.send_text(
                        json.dumps(
                            {
                                "type": "heartbeat",
                                "server_time": _now_iso(),
                                "interval_sec": HEARTBEAT_INTERVAL,
                            },
                            ensure_ascii=False,
                        )
                    )
                except Exception as e:
                    logger.warning(
                        f"[ws_room_events] heartbeat send failed room_id={room_id!r}: {e}"
                    )
                    break
            except WebSocketDisconnect:
                break
            except Exception as e:
                logger.warning(
                    f"[ws_room_events] receive error room_id={room_id!r}: {e}"
                )
                break
    finally:
        await push_manager.disconnect(room_id, websocket)
        remaining = push_manager.subscriber_count(room_id)
        logger.info(
            f"[ws_room_events] unregistered user_id={user_id!r} room_id={room_id!r} "
            f"remaining_subscribers={remaining}"
        )
