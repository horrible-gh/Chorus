from typing import Optional

from fastapi import APIRouter, Query

from modules import chat_manager
from schemas.chat import (
    ChatRoomCreate,
    ChatRoomResponse,
    Message,
    MessageSend,
    MessageSendResponse,
    Participant,
    ParticipantInvite,
    ParticipantRemove,
)

router = APIRouter()


@router.post("/rooms", response_model=ChatRoomResponse)
async def create_room(request: ChatRoomCreate):
    room, participants = chat_manager.create_room(
        user_id=request.user_id,
        title=request.title,
        mode=request.mode,
        initial_agent_ids=request.initial_agent_ids,
    )
    return {"request_id": request.request_id, "ok": True, "room": room, "participants": participants}


@router.get("/rooms")
async def list_rooms(owner_user_id: Optional[str] = Query(default=None)):
    return {"ok": True, "rooms": chat_manager.list_rooms(owner_user_id)}


@router.get("/rooms/{room_id}")
async def get_room(room_id: str):
    return {
        "ok": True,
        "room": chat_manager.get_room(room_id),
        "participants": chat_manager._room_participants(room_id),
    }


@router.delete("/rooms/{room_id}")
async def delete_room(room_id: str):
    chat_manager.delete_room(room_id)
    return {"ok": True}


@router.post("/rooms/{room_id}/participants", response_model=dict)
async def invite_agent(room_id: str, request: ParticipantInvite):
    participant = chat_manager.invite_agent(room_id, request.agent_id, request.invited_by_user_id)
    return {"request_id": request.request_id, "ok": True, "participant": Participant(**participant)}


@router.delete("/rooms/{room_id}/participants/{agent_id}", response_model=dict)
async def remove_agent(room_id: str, agent_id: str, request: ParticipantRemove):
    participant = chat_manager.remove_agent(room_id, agent_id, request.removed_by_user_id)
    return {"request_id": request.request_id, "ok": True, "participant": Participant(**participant)}


@router.post("/rooms/{room_id}/messages", response_model=MessageSendResponse)
async def send_message(room_id: str, request: MessageSend):
    """
    P001 message.send — route to sync (single agent) or async (multi-agent / whisper).

    Async path (send_message) is used when:
      - visibility == 'whisper'
      - recipient_agent_ids is non-empty
      - delivery_mode != 'append_history'
      - room message with 2+ active agents (T024)
    Otherwise the synchronous single-agent path (send_message_sync) is used.
    """
    use_async = (
        request.visibility == "whisper"
        or bool(request.recipient_agent_ids)
        or request.delivery_mode != "append_history"
    )

    if not use_async and request.visibility == "room":
        active_agents = [
            p
            for p in chat_manager._room_participants(room_id, active_only=True)
            if p["participant_type"] == "agent"
        ]
        if len(active_agents) >= 2:
            use_async = True

    if use_async:
        message, tasks = chat_manager.send_message(room_id, request.model_dump())
    else:
        message, tasks = chat_manager.send_message_sync(room_id, request.model_dump())

    return {"request_id": request.request_id, "ok": True, "message": message, "created_tasks": tasks}


@router.get("/rooms/{room_id}/messages")
async def list_messages(
    room_id: str,
    viewer_user_id: Optional[str] = Query(default=None),
    viewer_agent_id: Optional[str] = Query(default=None),
):
    messages = chat_manager.list_visible_messages(room_id, viewer_user_id, viewer_agent_id)
    return {"ok": True, "messages": [Message(**message) for message in messages]}

