from fastapi import APIRouter, HTTPException

from modules.routing import select_model
from schemas.routing import (
    RoutingErrorDetail,
    RoutingReselectRequest,
    RoutingSelectRequest,
    RoutingSelectResponse,
)

router = APIRouter()

_NO_MODEL_MSG = "No active model matches the request conditions."

_GRADE_NEXT = {"0급": "0.33급", "0.33급": "1급"}


def _error_response(request_id: str, code: str, message: str, field: str | None = None) -> RoutingSelectResponse:
    return RoutingSelectResponse(
        request_id=request_id,
        ok=False,
        error=RoutingErrorDetail(code=code, message=message, field=field),
    )


@router.post("/select", response_model=RoutingSelectResponse)
async def select_route(request: RoutingSelectRequest):
    try:
        decision = select_model(request.model_dump())
        return RoutingSelectResponse(request_id=request.request_id, ok=True, routing_decision=decision)
    except HTTPException as exc:
        detail = exc.detail if isinstance(exc.detail, dict) else {}
        code = detail.get("code", "ROUTING_ERROR")
        message = _NO_MODEL_MSG if code == "NO_AVAILABLE_MODEL" else str(exc.detail)
        return _error_response(request.request_id, code, message, detail.get("field"))


@router.post("/reselect", response_model=RoutingSelectResponse)
async def reselect_route(request: RoutingReselectRequest):
    """P002 routing.reselect_model — reselects a higher-grade model based on the previous failure reason."""
    escalated_grade_min = _GRADE_NEXT.get(request.previous_grade or "0급", "1급")
    select_data = {
        "request_id": request.request_id,
        "action": "routing.reselect_model",
        "source": request.source,
        "task_id": request.task_id,
        "preferred_runner": request.previous_runner,
        "previous_failure_code": request.failure_code,
        "previous_attempts": request.attempt,
        "allowed_grade_min": escalated_grade_min,
        "allowed_grade_max": "7.5급",
        "risk_hint": "normal",
        "can_modify_code": False,
        "can_modify_index": False,
        "requires_review": False,
        "read_paths_count": 0,
        "write_paths_count": 0,
    }
    try:
        decision = select_model(select_data)
        return RoutingSelectResponse(request_id=request.request_id, ok=True, routing_decision=decision)
    except HTTPException as exc:
        detail = exc.detail if isinstance(exc.detail, dict) else {}
        code = detail.get("code", "ROUTING_ERROR")
        message = _NO_MODEL_MSG if code == "NO_AVAILABLE_MODEL" else str(exc.detail)
        return _error_response(request.request_id, code, message, detail.get("field"))

