"""messages.py — cancel endpoint for AI generation (T068)

POST /rooms/{room_id}/messages/{generation_id}/cancel
"""
from fastapi import APIRouter, Request

from modules import task_manager

router = APIRouter()


@router.post("/rooms/{room_id}/messages/{generation_id}/cancel")
async def cancel_message(room_id: str, generation_id: str, request: Request):
    """Cancel an in-progress AI generation.

    P006 §3: cancel endpoint.
    Returns 200 on success, 409 for terminal states, 404/403/500 on error.
    """
    body = {}
    try:
        body = await request.json()
    except Exception:
        pass

    request_source = body.get("request_source", "user_click")
    if request_source not in ("user_click", "room_leave", "system"):
        request_source = "user_click"

    requested_by_user_id = body.get("requested_by_user_id") or None

    response_body, status_code = task_manager.cancel_generation(
        generation_id=generation_id,
        room_id=room_id,
        request_source=request_source,
        requested_by_user_id=requested_by_user_id,
    )
    from fastapi.responses import JSONResponse
    return JSONResponse(content=response_body, status_code=status_code)
