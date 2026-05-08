from typing import Any, List, Literal, Optional

from pydantic import BaseModel, Field, model_validator


RoomMode = Literal["append_history", "one_shot"]
Visibility = Literal["room", "whisper", "compression", "private"]
SenderType = Literal["user", "agent", "system"]


class ChatRoomCreate(BaseModel):
    request_id: Optional[str] = None
    user_id: str = Field(..., min_length=1)
    title: str = Field(..., min_length=1, max_length=200)
    mode: RoomMode = "append_history"
    initial_agent_ids: List[str] = Field(default_factory=list)


class ParticipantInvite(BaseModel):
    request_id: Optional[str] = None
    agent_id: str = Field(..., min_length=1)
    invited_by_user_id: str = Field(..., min_length=1)


class ParticipantRemove(BaseModel):
    request_id: Optional[str] = None
    agent_id: str = Field(..., min_length=1)
    removed_by_user_id: str = Field(..., min_length=1)


class MessageSender(BaseModel):
    sender_type: SenderType
    user_id: Optional[str] = None
    agent_id: Optional[str] = None

    @model_validator(mode="after")
    def validate_sender(self):
        if self.sender_type == "user" and not self.user_id:
            raise ValueError("user sender requires user_id")
        if self.sender_type == "agent" and not self.agent_id:
            raise ValueError("agent sender requires agent_id")
        return self


class MessageContent(BaseModel):
    content_type: Literal["text", "summary", "event", "error"] = "text"
    text: str = Field(..., min_length=1)


class MessageSend(BaseModel):
    request_id: Optional[str] = None
    sender: MessageSender
    visibility: Visibility = "room"
    recipient_agent_ids: List[str] = Field(default_factory=list)
    content: MessageContent
    delivery_mode: RoomMode = "append_history"
    context_mode: Optional[Literal["pinned", "rotation", "none"]] = "none"
    pinned_message_id: Optional[str] = None
    rotation_n: int = Field(default=5, ge=1, le=9999)

    @model_validator(mode="after")
    def validate_visibility(self):
        if self.visibility == "whisper" and not self.recipient_agent_ids:
            raise ValueError("whisper message requires recipient_agent_ids")
        return self


class Participant(BaseModel):
    participant_id: str
    room_id: str
    participant_type: Literal["user", "agent"]
    user_id: Optional[str] = None
    agent_id: Optional[str] = None
    display_name: str
    status: Literal["active", "inactive"]
    joined_at: str
    left_at: Optional[str] = None


class ChatRoom(BaseModel):
    room_id: str
    title: str
    mode: RoomMode
    status: str
    owner_user_id: str
    active_history_mode: str
    base_summary_message_id: Optional[str] = None
    created_at: str
    updated_at: str
    archived_at: Optional[str] = None


class Message(BaseModel):
    message_id: str
    room_id: str
    sender_type: SenderType
    sender_user_id: Optional[str] = None
    sender_agent_id: Optional[str] = None
    visibility: Visibility
    recipient_agent_ids: List[str] = Field(default_factory=list)
    content_type: str
    text: str
    delivery_mode: RoomMode
    history_state: str
    source_task_id: Optional[str] = None
    created_at: str
    context_usage: Optional[Any] = None


class RoomEvent(BaseModel):
    event_id: str
    room_id: str
    event_type: str
    actor_user_id: Optional[str] = None
    actor_agent_id: Optional[str] = None
    text: str
    created_at: str


class ChatRoomResponse(BaseModel):
    request_id: Optional[str] = None
    ok: bool = True
    room: ChatRoom
    participants: List[Participant]


class MessageSendResponse(BaseModel):
    request_id: Optional[str] = None
    ok: bool = True
    message: Message
    created_tasks: List[dict] = Field(default_factory=list)
    generation_id: Optional[str] = None
    status: Optional[str] = None

