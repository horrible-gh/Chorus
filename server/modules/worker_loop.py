import asyncio
import uuid
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import HTTPException

import LogAssist.log as logger
from modules.chat_manager import JST, STORE, get_agent, now_iso
from modules.routing import select_model

LEASE_TTL_MINUTES = 15
MAX_ATTEMPTS_ZERO_GRADE = 2
MAX_ATTEMPTS_NORMAL = 3
BASE_BACKOFF_SECONDS = 60
MAX_BACKOFF_SECONDS = 900

POLL_INTERVAL_SECONDS = 3
_POLL_WORKER_ID = "server-poll-worker"


def _publish_message_completed(task_id: str, task: dict) -> None:
    """Publishes the message_completed event after AI task completion and message storage."""
    room_id = task.get("input_json", {}).get("room_id")
    if not room_id:
        logger.warning(
            f"[_publish_message_completed] room_id not found in input_json for task {task_id!r}, skip publish"
        )
        return
    from modules.push_manager import push_manager
    payload = {
        "type": "message_completed",
        "room_id": room_id,
        "task_id": task_id,
        "timestamp": now_iso(),
    }
    try:
        loop = asyncio.get_running_loop()
        loop.create_task(push_manager.publish(room_id, payload))
        logger.info(
            f"[_publish_message_completed] scheduled publish room_id={room_id!r} task_id={task_id!r}"
        )
    except RuntimeError:
        logger.warning(
            f"[_publish_message_completed] no running event loop, cannot publish for task {task_id!r}"
        )


def _task_response(task: dict) -> dict:
    return task


def create_task(payload: dict, route: bool = True) -> dict:
    logger.debug(f"[create_task] enter — title={payload.get('title')!r} task_type={payload.get('task_type')!r} assigned_agent_id={payload.get('assigned_agent_id')!r}")
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
                    "preferred_runner": payload.get("preferred_runner") or "copilot",
                    "default_model": payload.get("default_model"),
                    "default_grade": payload.get("default_grade"),
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
    logger.debug(f"[create_agent_response_task] enter — room_id={room_id!r} message_id={message.get('message_id')!r} agent_id={agent_id!r}")
    task_input: dict = {"room_id": room_id, "message_id": message["message_id"], "instruction": message["text"]}
    if context_messages:
        task_input["context_messages"] = context_messages
    agent = get_agent(agent_id)
    preferred_runner = (agent.get("default_runner") or "copilot") if agent else "copilot"
    default_model = agent.get("default_model") if agent else None
    default_grade = agent.get("default_grade") if agent else None
    task = create_task(
        {
            "source": "agent_chat",
            "title": f"Agent response for {message['message_id']}",
            "task_type": "agent_response",
            "priority": "normal",
            "assigned_agent_id": agent_id,
            "preferred_runner": preferred_runner,
            "default_model": default_model,
            "default_grade": default_grade,
            "input": task_input,
            "constraints": {"can_modify_code": False, "can_modify_index": False, "requires_review": False},
        }
    )
    generation_id = "gen_" + str(uuid.uuid4())
    task = STORE.update_task(
        task["task_id"],
        {
            "generation_id": generation_id,
            "room_id": room_id,
            "source_message_id": message["message_id"],
            "updated_at": now_iso(),
        },
    )
    return task


def list_tasks(status: Optional[str] = None) -> List[dict]:
    return STORE.list_tasks(status)


def get_task(task_id: str) -> dict:
    task = STORE.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="TASK_NOT_FOUND")
    return task


def acquire_lease(task_id: str, payload: dict) -> tuple[dict, dict]:
    logger.debug(f"[acquire_lease] enter — task_id={task_id!r} worker_id={payload.get('worker_id')!r} job_id={payload.get('job_id')!r}")
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
    logger.debug(f"[update_progress] enter — task_id={task_id!r} message={payload.get('message')!r}")
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
    logger.debug(f"[complete_task] enter — task_id={task_id!r} worker_id={payload.get('worker_id')!r}")
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
                    "message": "ExLow-grade worker can return only one artifact path.",
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
        result_json = {"summary": payload.get("summary"), "artifact_paths": payload.get("artifact_paths", [])}
        task = STORE.update_task(
            task_id,
            {
                "result_json": result_json,
                "status": "review_required" if task["constraints_json"].get("requires_review") else "done",
                "completed_at": now,
                "updated_at": now,
            },
        )
        
        if task["task_type"] == "agent_response":
            from modules.chat_manager import persist_agent_response_message
            logger.debug(f"[complete_task] calling persist_agent_response_message for task {task_id}")
            try:
                msg = persist_agent_response_message(task, result_json)
                if msg is None:
                    logger.error(f"[complete_task] persist_agent_response_message returned None for task {task_id}")
                else:
                    _publish_message_completed(task_id, task)
            except Exception as e:
                logger.error(f"[complete_task] persist_agent_response_message raised an exception for task {task_id}: {e}")
        
        return task, run


def fail_task(task_id: str, payload: dict) -> tuple[dict, dict]:
    logger.debug(f"[fail_task] enter — task_id={task_id!r} worker_id={payload.get('worker_id')!r} code={payload.get('code')!r}")
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


# ── Polling loop ─────────────────────────────────────────────────────────────


async def _dispatch_one_task(task: dict) -> None:
    """Processes one runnable agent_response task."""
    from modules.chat_manager import _call_ai_sync, _build_chat_history

    task_id = task["task_id"]
    logger.debug(f"[poll_loop] task dispatch start — task_id={task_id!r}")

    job_id = f"job_{uuid.uuid4().hex[:12]}"
    try:
        lease, task = acquire_lease(task_id, {"worker_id": _POLL_WORKER_ID, "job_id": job_id})
    except Exception as e:
        logger.debug(f"[poll_loop] lease acquire failed — task_id={task_id!r}: {e}")
        return

    lease_id = lease["lease_id"]
    logger.debug(f"[poll_loop] lease acquired — task_id={task_id!r} lease_id={lease_id!r}")

    agent_id = task.get("assigned_agent_id")
    agent = STORE.get_agent(agent_id) if agent_id else None

    task_input = task.get("input_json", {})
    room_id = task_input.get("room_id")
    user_message_id = task_input.get("message_id")
    instruction = task_input.get("instruction", "")

    history = _build_chat_history(room_id, user_message_id) if room_id and user_message_id else []

    runner = task.get("assigned_runner") or "copilot"
    model = task.get("assigned_model") or "claude-sonnet-4-5"

    settings = agent.get("settings_json") or {} if agent else {}
    if isinstance(settings, str):
        import json as _json
        try:
            settings = _json.loads(settings)
        except Exception:
            settings = {}
    provider_token_id = settings.get("provider_token_id")
    work_dir = settings.get("work_dir") or None
    allowed_dirs = settings.get("allowed_dirs") or []

    logger.debug(f"[poll_loop] AI call start — task_id={task_id!r} runner={runner!r} model={model!r}")
    try:
        ai_text = await asyncio.to_thread(
            _call_ai_sync,
            runner=runner,
            model=model,
            system_prompt=agent.get("system_prompt") if agent else None,
            history=history,
            user_text=instruction,
            pinned_context=agent.get("pinned_context") if agent else None,
            provider_token_id=provider_token_id,
            work_dir=work_dir,
            allowed_dirs=allowed_dirs,
        )
        logger.debug(f"[poll_loop] AI call succeeded — task_id={task_id!r}")
        complete_task(task_id, {
            "worker_id": _POLL_WORKER_ID,
            "lease_id": lease_id,
            "summary": ai_text,
            "artifact_paths": [],
        })
        logger.info(f"[poll_loop] task completed — task_id={task_id!r}")
    except Exception as e:
        logger.error(f"[poll_loop] AI call failed — task_id={task_id!r}: {e}")
        try:
            fail_task(task_id, {
                "worker_id": _POLL_WORKER_ID,
                "lease_id": lease_id,
                "code": "AI_CALL_FAILED",
                "message": str(e),
                "retryable": True,
            })
        except Exception as fe:
            logger.error(f"[poll_loop] fail_task call failed — task_id={task_id!r}: {fe}")


async def _dispatch_pending_tasks() -> None:
    """Fetches runnable agent_response tasks and processes them concurrently."""
    now = datetime.now(JST)
    runnable = [
        t for t in STORE.list_tasks()
        if t["task_type"] == "agent_response"
        and t["status"] in ("queued", "retry_scheduled")
        and (
            t["status"] != "retry_scheduled"
            or not t.get("next_run_at")
            or datetime.fromisoformat(t["next_run_at"]) <= now
        )
    ]

    results = await asyncio.gather(
        *(_dispatch_one_task(task) for task in runnable),
        return_exceptions=True,
    )
    for task, result in zip(runnable, results):
        if isinstance(result, Exception):
            logger.error(f"[poll_loop] task dispatch crashed — task_id={task['task_id']!r}: {result}")


async def poll_loop() -> None:
    """Server background polling loop — periodically processes queued agent_response tasks."""
    logger.info("[poll_loop] polling loop started")
    try:
        while True:
            await asyncio.sleep(POLL_INTERVAL_SECONDS)
            try:
                await _dispatch_pending_tasks()
            except Exception as e:
                logger.error(f"[poll_loop] exception during polling: {e}")
    except asyncio.CancelledError:
        logger.info("[poll_loop] polling loop stopped (CancelledError)")
