"""WebSocket connection pool manager — publishes events to subscribers per room_id."""
from __future__ import annotations

import asyncio
import json
from typing import Dict, List

from fastapi import WebSocket

import LogAssist.log as logger


class PushManager:
    """Manages per-room_id WebSocket connection pools and publishes events."""

    def __init__(self) -> None:
        self._connections: Dict[str, List[WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, room_id: str, websocket: WebSocket) -> None:
        async with self._lock:
            if room_id not in self._connections:
                self._connections[room_id] = []
            self._connections[room_id].append(websocket)
        count = len(self._connections.get(room_id, []))
        logger.info(
            f"[PushManager.connect] room_id={room_id!r} subscribers={count}"
        )

    async def disconnect(self, room_id: str, websocket: WebSocket) -> None:
        async with self._lock:
            if room_id in self._connections:
                try:
                    self._connections[room_id].remove(websocket)
                except ValueError:
                    pass
                if not self._connections[room_id]:
                    del self._connections[room_id]
        count = len(self._connections.get(room_id, []))
        logger.info(
            f"[PushManager.disconnect] room_id={room_id!r} remaining_subscribers={count}"
        )

    def subscriber_count(self, room_id: str) -> int:
        """Returns the current subscriber count for a room_id (lock-free read)."""
        return len(self._connections.get(room_id, []))

    async def publish(self, room_id: str, payload: dict) -> None:
        """Publish an event to all subscribers of the given room."""
        async with self._lock:
            connections = list(self._connections.get(room_id, []))

        if not connections:
            logger.debug(f"[PushManager.publish] room_id={room_id!r} no subscribers")
            return

        logger.info(
            f"[PushManager.publish] broadcasting type={payload.get('type')!r} "
            f"room_id={room_id!r} subscribers={len(connections)}"
        )
        message = json.dumps(payload, ensure_ascii=False)
        dead: List[WebSocket] = []
        for ws in connections:
            try:
                await ws.send_text(message)
                logger.debug(
                    f"[PushManager.publish] sent type={payload.get('type')!r} room_id={room_id!r}"
                )
            except Exception as e:
                logger.warning(
                    f"[PushManager.publish] send failed room_id={room_id!r}: {e}"
                )
                dead.append(ws)

        for ws in dead:
            await self.disconnect(room_id, ws)


push_manager = PushManager()
