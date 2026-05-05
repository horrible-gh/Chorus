from typing import Literal, Optional

from pydantic import BaseModel, Field


class RoutingSelectRequest(BaseModel):
    request_id: str = Field(..., min_length=1)
    action: str = "routing.select_model"
    source: Literal["agent_chat", "worker_loop", "manual"]
    room_id: Optional[str] = None
    message_id: Optional[str] = None
    task_id: Optional[str] = None
    agent_id: Optional[str] = None
    task_intent: Optional[str] = None
    risk_hint: Literal["low", "normal", "high"] = "normal"
    preferred_runner: Optional[str] = "copilot"
    allowed_grade_min: str = "0급"
    allowed_grade_max: str = "1급"
    title: Optional[str] = None
    instruction: Optional[str] = None
    message_text: Optional[str] = None
    read_paths_count: int = 0
    write_paths_count: int = 0
    previous_attempts: int = 0
    previous_failure_code: Optional[str] = None
    can_modify_code: bool = False
    can_modify_index: bool = False
    requires_review: bool = False


class RoutingReselectRequest(BaseModel):
    """P002 routing.reselect_model — 실행 결과 기반 재라우팅 요청."""

    request_id: str = Field(..., min_length=1)
    action: str = "routing.reselect_model"
    source: Literal["agent_chat", "worker_loop", "manual"]
    task_id: Optional[str] = None
    previous_routing_id: str
    previous_runner: Optional[str] = None
    previous_model: Optional[str] = None
    previous_grade: Optional[str] = None
    failure_code: str
    failure_text: Optional[str] = None
    attempt: int = 1


class RoutingDecision(BaseModel):
    routing_id: str
    selected_runner: Optional[str] = None
    selected_model: Optional[str] = None
    selected_grade: Optional[str] = None
    decision: Literal["selected", "escalated", "blocked"]
    reason_code: str
    reason_text: str
    requires_review: bool
    escalation_target: Optional[str] = None
    task_intent: str
    complexity_score: int
    risk_score: int
    confidence: float
    created_at: str


class RoutingErrorDetail(BaseModel):
    """P002 오류 응답 상세."""

    code: str
    message: str
    field: Optional[str] = None


class RoutingSelectResponse(BaseModel):
    request_id: str
    ok: bool = True
    routing_decision: Optional[RoutingDecision] = None
    error: Optional[RoutingErrorDetail] = None

