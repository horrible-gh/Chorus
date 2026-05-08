from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, Field


class TaskConstraints(BaseModel):
    can_modify_code: bool = False
    can_modify_index: bool = False
    requires_review: bool = False


class TaskCreate(BaseModel):
    request_id: Optional[str] = None
    created_by_user_id: Optional[str] = None
    source: Literal["manual", "agent_chat", "recovery", "system"] = "manual"
    title: str = Field(..., min_length=1, max_length=200)
    task_type: str = Field(..., min_length=1, max_length=60)
    priority: Literal["low", "normal", "high"] = "normal"
    assigned_agent_id: Optional[str] = None
    input: Dict[str, Any] = Field(default_factory=dict)
    constraints: TaskConstraints = Field(default_factory=TaskConstraints)


class LeaseAcquire(BaseModel):
    request_id: Optional[str] = None
    worker_id: str = Field(..., min_length=1)
    job_id: str = Field(..., min_length=1)
    trace_id: Optional[str] = None


class TaskProgress(BaseModel):
    request_id: Optional[str] = None
    worker_id: str
    lease_id: str
    state: str = "working"
    message: str
    artifact_path: Optional[str] = None


class TaskComplete(BaseModel):
    request_id: Optional[str] = None
    worker_id: str
    lease_id: str
    status: Literal["succeeded"] = "succeeded"
    summary: str = ""
    artifact_paths: List[str] = Field(default_factory=list)
    log_path: Optional[str] = None


class TaskFail(BaseModel):
    request_id: Optional[str] = None
    worker_id: str
    lease_id: Optional[str] = None
    code: str
    message: str
    retryable: bool = True
    log_path: Optional[str] = None


class Task(BaseModel):
    task_id: str
    created_by_user_id: Optional[str] = None
    source: str
    title: str
    task_type: str
    priority: str
    status: str
    assigned_agent_id: Optional[str] = None
    routing_id: Optional[str] = None
    assigned_runner: Optional[str] = None
    assigned_model: Optional[str] = None
    assigned_grade: Optional[str] = None
    attempt: int
    max_attempts: int
    input_json: Dict[str, Any]
    constraints_json: Dict[str, Any]
    result_json: Optional[Dict[str, Any]] = None
    failure_code: Optional[str] = None
    failure_text: Optional[str] = None
    next_run_at: Optional[str] = None
    last_progress_at: Optional[str] = None
    last_progress_message: Optional[str] = None
    created_at: str
    updated_at: str
    completed_at: Optional[str] = None
    generation_id: Optional[str] = None
    room_id: Optional[str] = None
    source_message_id: Optional[str] = None
    cancelled_at: Optional[str] = None
    cancel_requested_at: Optional[str] = None


class Lease(BaseModel):
    lease_id: str
    task_id: str
    job_id: str
    worker_id: str
    status: str
    acquired_at: str
    expires_at: str
    released_at: Optional[str] = None
    trace_id: str

