"""task_manager.py — generation cancel state transition logic (T068)

Handles cancel requests: state checks, DB updates, and cancel log insertion.
"""
from __future__ import annotations

import uuid
from typing import Optional

import LogAssist.log as logger
from modules.chat_manager import STORE, now_iso

# Server-side task statuses that map to "active generation" states
_CANCELLABLE_STATUSES = {"queued", "running", "retry_scheduled"}
# Server-side task statuses that map to terminal states
_TERMINAL_COMPLETED = {"done", "review_required"}
_TERMINAL_FAILED = {"failed"}
_TERMINAL_CANCELLED = {"cancelled"}


def cancel_generation(
    generation_id: str,
    room_id: str,
    request_source: str,
    requested_by_user_id: Optional[str] = None,
) -> dict:
    """Cancel a generation by generation_id.

    Args:
        generation_id: The `gen_*` ID returned when the message was sent.
        room_id:        The room the generation belongs to (used for ownership check).
        request_source: One of "user_click", "room_leave", "system".
        requested_by_user_id: User ID of the requester; None for automatic cancels.

    Returns:
        A dict with the cancel outcome suitable for the HTTP response.
    """
    requested_at = now_iso()

    task = STORE.get_task_by_generation_id(generation_id)

    if task is None:
        _log_cancel(
            generation_id=generation_id,
            task_id="unknown",
            room_id=room_id,
            requested_by_user_id=requested_by_user_id,
            request_source=request_source,
            result="not_found",
            requested_at=requested_at,
            processed_at=now_iso(),
        )
        return {
            "generation_id": generation_id,
            "error_code": "GENERATION_NOT_FOUND",
            "message": "The specified generation_id was not found.",
        }, 404

    # Room ownership check
    task_room_id = task.get("room_id")
    if task_room_id and task_room_id != room_id:
        _log_cancel(
            generation_id=generation_id,
            task_id=task["task_id"],
            room_id=room_id,
            requested_by_user_id=requested_by_user_id,
            request_source=request_source,
            result="not_found",
            requested_at=requested_at,
            processed_at=now_iso(),
        )
        return {
            "error_code": "PERMISSION_DENIED",
            "message": "You do not have permission to cancel this generation.",
        }, 403

    status = task.get("status", "")

    # Already terminal states
    if status in _TERMINAL_COMPLETED:
        completed_at = task.get("completed_at")
        # Retroactively remove the AI response so it does not appear to the user.
        try:
            deleted = STORE.delete_agent_messages_for_task(task["task_id"])
            if deleted:
                logger.info(
                    f"[cancel_generation] retroactively deleted {deleted} agent message(s)"
                    f" for generation_id={generation_id!r} task_id={task['task_id']!r}"
                )
        except Exception as exc:
            logger.warning(
                f"[cancel_generation] failed to delete agent messages for"
                f" task_id={task['task_id']!r}: {exc}"
            )
        _log_cancel(
            generation_id=generation_id,
            task_id=task["task_id"],
            room_id=room_id,
            requested_by_user_id=requested_by_user_id,
            request_source=request_source,
            result="already_completed",
            requested_at=requested_at,
            processed_at=now_iso(),
        )
        return {
            "generation_id": generation_id,
            "room_id": room_id,
            "status": "already_completed",
            "error_code": "GENERATION_ALREADY_COMPLETED",
            "message": "The AI generation has already completed.",
            "completed_at": completed_at,
        }, 409

    if status in _TERMINAL_CANCELLED:
        cancelled_at = task.get("cancelled_at")
        _log_cancel(
            generation_id=generation_id,
            task_id=task["task_id"],
            room_id=room_id,
            requested_by_user_id=requested_by_user_id,
            request_source=request_source,
            result="already_cancelled",
            requested_at=requested_at,
            processed_at=now_iso(),
        )
        return {
            "generation_id": generation_id,
            "room_id": room_id,
            "status": "already_cancelled",
            "error_code": "GENERATION_ALREADY_CANCELLED",
            "message": "The generation request has already been cancelled.",
            "cancelled_at": cancelled_at,
        }, 409

    if status in _TERMINAL_FAILED:
        _log_cancel(
            generation_id=generation_id,
            task_id=task["task_id"],
            room_id=room_id,
            requested_by_user_id=requested_by_user_id,
            request_source=request_source,
            result="already_failed",
            requested_at=requested_at,
            processed_at=now_iso(),
        )
        return {
            "generation_id": generation_id,
            "room_id": room_id,
            "status": "already_failed",
            "error_code": "GENERATION_ALREADY_FAILED",
            "message": "The generation request has already failed.",
        }, 409

    # Perform the cancellation
    task_id = task["task_id"]
    cancelled_at = now_iso()
    try:
        with STORE.transaction():
            # Single UPDATE to cancelled state with all timing fields
            STORE.update_task(
                task_id,
                {
                    "status": "cancelled",
                    "cancel_requested_at": requested_at,
                    "cancelled_at": cancelled_at,
                    "updated_at": cancelled_at,
                },
            )
            _log_cancel(
                generation_id=generation_id,
                task_id=task_id,
                room_id=room_id,
                requested_by_user_id=requested_by_user_id,
                request_source=request_source,
                result="cancelled",
                requested_at=requested_at,
                processed_at=cancelled_at,
            )

            # Propagate cancellation to sibling tasks spawned from the same
            # user message (multi-agent scenario where each agent gets its own task).
            source_message_id = task.get("source_message_id")
            if source_message_id:
                status_placeholders = ",".join("?" * len(_CANCELLABLE_STATUSES))
                sibling_rows = STORE._fetch_all(
                    f"SELECT * FROM tasks"
                    f" WHERE source_message_id = ? AND task_id != ?"
                    f" AND status IN ({status_placeholders})",
                    [source_message_id, task_id, *_CANCELLABLE_STATUSES],
                )
                for row in sibling_rows:
                    sibling = STORE._task_from_row(row)
                    if not sibling:
                        continue
                    STORE.update_task(
                        sibling["task_id"],
                        {
                            "status": "cancelled",
                            "cancel_requested_at": requested_at,
                            "cancelled_at": cancelled_at,
                            "updated_at": cancelled_at,
                        },
                    )
                    _log_cancel(
                        generation_id=generation_id,
                        task_id=sibling["task_id"],
                        room_id=room_id,
                        requested_by_user_id=requested_by_user_id,
                        request_source=request_source,
                        result="cancelled",
                        requested_at=requested_at,
                        processed_at=cancelled_at,
                    )
                    logger.info(
                        f"[cancel_generation] propagated cancel to sibling"
                        f" task_id={sibling['task_id']!r}"
                        f" (generation_id={generation_id!r})"
                    )

        logger.info(
            f"[cancel_generation] cancelled generation_id={generation_id!r} task_id={task_id!r}"
        )
        return {
            "generation_id": generation_id,
            "room_id": room_id,
            "status": "cancelled",
            "cancelled_at": cancelled_at,
            "message": "Generation has been cancelled.",
        }, 200

    except Exception as exc:
        logger.error(f"[cancel_generation] error cancelling task_id={task_id!r}: {exc}")
        try:
            _log_cancel(
                generation_id=generation_id,
                task_id=task_id,
                room_id=room_id,
                requested_by_user_id=requested_by_user_id,
                request_source=request_source,
                result="server_error",
                result_detail=str(exc),
                requested_at=requested_at,
                processed_at=now_iso(),
            )
        except Exception:
            pass
        return {
            "error_code": "SERVER_ERROR",
            "message": "An internal server error occurred.",
        }, 500


def _log_cancel(
    generation_id: str,
    task_id: str,
    room_id: str,
    requested_by_user_id: Optional[str],
    request_source: str,
    result: str,
    requested_at: str,
    processed_at: Optional[str] = None,
    result_detail: Optional[str] = None,
) -> None:
    try:
        log_id = str(uuid.uuid4())
        STORE.insert_cancel_log(
            {
                "log_id": log_id,
                "generation_id": generation_id,
                "task_id": task_id,
                "room_id": room_id,
                "requested_by_user_id": requested_by_user_id,
                "request_source": request_source,
                "result": result,
                "result_detail": result_detail,
                "requested_at": requested_at,
                "processed_at": processed_at,
            }
        )
    except Exception as exc:
        logger.warning(f"[_log_cancel] failed to insert cancel log: {exc}")
