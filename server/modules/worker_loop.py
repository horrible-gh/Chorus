from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import HTTPException

from modules.chat_manager import JST, STORE, get_agent, now_iso
from modules.routing import select_model

LEASE_TTL_MINUTES = 15
MAX_ATTEMPTS_ZERO_GRADE = 2
MAX_ATTEMPTS_NORMAL = 3
BASE_BACKOFF_SECONDS = 60
MAX_BACKOFF_SECONDS = 900


def _task_response(task: dict) -> dict:
    return task


def create_task(payload: dict, route: bool = True) -> dict:
    with STORE.transaction():
        if payload.get("assigned_agent_id"):
            get_agent(payload["assigned_agent_id"])

        task_id = STORE.next_id("task")
        created_at = now_iso()
        constraints = payload.get("constraints") or {}
        task = STORE.insert_task(
            {
                "task_id": task_id,
                "created_by_user_id": payload.get("created_by_user_id"),
                "source": payload.get("source", "manual"),
                "title": payload["title"],
                "task_type": payload["task_type"],
                "priority": payload.get("priority", "normal"),
                "status": "queued",
                "assigned_agent_id": payload.get("assigned_agent_id"),
                "routing_id": None,
                "assigned_runner": None,
                "assigned_model": None,
                "assigned_grade": None,
                "attempt": 0,
                "max_attempts": MAX_ATTEMPTS_NORMAL,
                "input_json": payload.get("input", {}),
                "constraints_json": constraints,
                "result_json": None,
                "failure_code": None,
                "failure_text": None,
                "next_run_at": None,
                "last_progress_at": None,
                "last_progress_message": None,
                "created_at": created_at,
                "updated_at": created_at,
                "completed_at": None,
            }
        )
        if route:
            decision = select_model(
                {
                    "request_id": payload.get("request_id") or STORE.next_id("req"),
                    "source": "worker_loop",
                    "task_id": task_id,
                    "agent_id": task["assigned_agent_id"],
                    "task_intent": task["task_type"],
                    "risk_hint": "low" if task["task_type"] in ("document_draft", "agent_response") else "normal",
                    "preferred_runner": "copilot",
                    "allowed_grade_min": "0급",
                    "allowed_grade_max": "1급",
                    "title": task["title"],
                    "instruction": str(task["input_json"].get("instruction", "")),
                    "read_paths_count": len(task["input_json"].get("read_paths", [])),
                    "write_paths_count": len(task["input_json"].get("write_paths", [])),
                    "can_modify_code": constraints.get("can_modify_code", False),
                    "can_modify_index": constraints.get("can_modify_index", False),
                    "requires_review": constraints.get("requires_review", False),
                }
            )
            task = STORE.update_task(
                task_id,
                {
                    "routing_id": decision["routing_id"],
                    "assigned_runner": decision["selected_runner"],
                    "assigned_model": decision["selected_model"],
                    "assigned_grade": decision["selected_grade"],
                    "max_attempts": MAX_ATTEMPTS_ZERO_GRADE
                    if decision["selected_grade"] == "0급"
                    else MAX_ATTEMPTS_NORMAL,
                    "updated_at": now_iso(),
                },
            )
        return _task_response(task)


def create_agent_response_task(room_id: str, message: dict, agent_id: str, context_messages: Optional[list] = None) -> dict:
    task_input: dict = {"room_id": room_id, "message_id": message["message_id"], "instruction": message["text"]}
    if context_messages:
        task_input["context_messages"] = context_messages
    return create_task(
        {
            "source": "agent_chat",
            "title": f"Agent response for {message['message_id']}",
            "task_type": "agent_response",
            "priority": "normal",
            "assigned_agent_id": agent_id,
            "input": task_input,
            "constraints": {"can_modify_code": False, "can_modify_index": False, "requires_review": False},
        }
    )


def list_tasks(status: Optional[str] = None) -> List[dict]:
    return STORE.list_tasks(status)


def get_task(task_id: str) -> dict:
    task = STORE.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="TASK_NOT_FOUND")
    return task


def acquire_lease(task_id: str, payload: dict) -> tuple[dict, dict]:
    with STORE.transaction():
        task = get_task(task_id)
        if task["status"] not in ("queued", "retry_scheduled"):
            raise HTTPException(status_code=409, detail="TASK_NOT_RUNNABLE")

        now = datetime.now(JST)
        for lease in STORE.list_active_leases_for_task(task_id):
            expires_at = datetime.fromisoformat(lease["expires_at"])
            if expires_at > now:
                raise HTTPException(status_code=409, detail="LEASE_ALREADY_ACQUIRED")
            STORE.update_lease(lease["lease_id"], {"status": "expired"})

        lease_id = STORE.next_id("lease")
        trace_id = payload.get("trace_id") or STORE.next_id("trace")
        lease = STORE.insert_lease(
            {
                "lease_id": lease_id,
                "task_id": task_id,
                "job_id": payload["job_id"],
                "worker_id": payload["worker_id"],
                "status": "active",
                "acquired_at": now.isoformat(timespec="seconds"),
                "expires_at": (now + timedelta(minutes=LEASE_TTL_MINUTES)).isoformat(timespec="seconds"),
                "released_at": None,
                "trace_id": trace_id,
            }
        )
        task = STORE.update_task(
            task_id,
            {
                "status": "running",
                "attempt": task["attempt"] + 1,
                "last_progress_at": now.isoformat(timespec="seconds"),
                "updated_at": now.isoformat(timespec="seconds"),
            },
        )
        return lease, task


def _active_lease(task_id: str, lease_id: str, worker_id: str) -> dict:
    lease = STORE.get_lease(lease_id)
    if not lease or lease["task_id"] != task_id:
        raise HTTPException(status_code=404, detail="LEASE_NOT_FOUND")
    if lease["status"] != "active":
        raise HTTPException(status_code=409, detail="LEASE_NOT_ACTIVE")
    if lease["worker_id"] != worker_id:
        raise HTTPException(status_code=403, detail="LEASE_OWNER_MISMATCH")
    if datetime.fromisoformat(lease["expires_at"]) <= datetime.now(JST):
        STORE.update_lease(lease_id, {"status": "expired"})
        raise HTTPException(status_code=409, detail="LEASE_EXPIRED")
    return lease


def update_progress(task_id: str, payload: dict) -> dict:
    with STORE.transaction():
        get_task(task_id)
        lease = _active_lease(task_id, payload["lease_id"], payload["worker_id"])
        now = datetime.now(JST)
        STORE.update_lease(
            lease["lease_id"],
            {"expires_at": (now + timedelta(minutes=LEASE_TTL_MINUTES)).isoformat(timespec="seconds")},
        )
        task = STORE.update_task(
            task_id,
            {
                "last_progress_at": now.isoformat(timespec="seconds"),
                "last_progress_message": payload["message"],
                "updated_at": now.isoformat(timespec="seconds"),
            },
        )
        return task


def complete_task(task_id: str, payload: dict) -> tuple[dict, dict]:
    with STORE.transaction():
        task = get_task(task_id)
        lease = _active_lease(task_id, payload["lease_id"], payload["worker_id"])
        if task["assigned_grade"] == "0급" and len(payload.get("artifact_paths", [])) > 1:
            return fail_task(
                task_id,
                {
                    "worker_id": payload["worker_id"],
                    "lease_id": payload["lease_id"],
                    "code": "OUTPUT_LIMIT_EXCEEDED",
                    "message": "0급 워커는 산출물 경로를 하나만 반환할 수 있습니다.",
                    "retryable": False,
                },
            )

        now = now_iso()
        STORE.update_lease(lease["lease_id"], {"status": "released", "released_at": now})
        run = STORE.insert_worker_run(
            {
                "run_id": STORE.next_id("run"),
                "task_id": task_id,
                "lease_id": lease["lease_id"],
                "worker_id": payload["worker_id"],
                "runner": task.get("assigned_runner") or "prototype",
                "model": task.get("assigned_model") or "prototype",
                "grade": task.get("assigned_grade") or "0급",
                "attempt": task["attempt"],
                "result_status": "succeeded",
                "summary": payload.get("summary"),
                "artifact_paths_json": payload.get("artifact_paths", []),
                "log_path": payload.get("log_path"),
                "failure_code": None,
                "failure_text": None,
                "started_at": lease["acquired_at"],
                "finished_at": now,
            }
        )
        task = STORE.update_task(
            task_id,
            {
                "result_json": {"summary": payload.get("summary"), "artifact_paths": payload.get("artifact_paths", [])},
                "status": "review_required" if task["constraints_json"].get("requires_review") else "done",
                "completed_at": now,
                "updated_at": now,
            },
        )
        return task, run


def fail_task(task_id: str, payload: dict) -> tuple[dict, dict]:
    with STORE.transaction():
        task = get_task(task_id)
        lease = None
        if payload.get("lease_id"):
            lease = _active_lease(task_id, payload["lease_id"], payload["worker_id"])
            STORE.update_lease(lease["lease_id"], {"status": "released", "released_at": now_iso()})

        finished_at = now_iso()
        run = STORE.insert_worker_run(
            {
                "run_id": STORE.next_id("run"),
                "task_id": task_id,
                "lease_id": payload.get("lease_id"),
                "worker_id": payload["worker_id"],
                "runner": task.get("assigned_runner") or "prototype",
                "model": task.get("assigned_model") or "prototype",
                "grade": task.get("assigned_grade") or "0급",
                "attempt": task["attempt"],
                "result_status": "failed",
                "summary": None,
                "artifact_paths_json": [],
                "log_path": payload.get("log_path"),
                "failure_code": payload["code"],
                "failure_text": payload["message"],
                "started_at": lease["acquired_at"] if lease else finished_at,
                "finished_at": finished_at,
            }
        )

        updates = {
            "failure_code": payload["code"],
            "failure_text": payload["message"],
            "updated_at": now_iso(),
        }
        if not payload.get("retryable", True) or task["attempt"] >= task["max_attempts"]:
            updates["status"] = "failed"
        else:
            delay = min(BASE_BACKOFF_SECONDS * (2 ** max(task["attempt"] - 1, 0)), MAX_BACKOFF_SECONDS)
            updates["status"] = "retry_scheduled"
            updates["next_run_at"] = (datetime.now(JST) + timedelta(seconds=delay)).isoformat(timespec="seconds")
        task = STORE.update_task(task_id, updates)
        return task, run
