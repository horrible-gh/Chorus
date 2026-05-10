from __future__ import annotations

import json
import os
import platform
import re
import shutil
import subprocess
import queue
import threading
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator, List, Optional

from fastapi import HTTPException

import LogAssist.log as logger
from config import get_db_instance, get_sqloader_instance

JST = timezone(timedelta(hours=9))
SERVER_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = Path(__file__).resolve().parents[2]
_ANSI_ESCAPE_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
_LABELED_SECRET_RE = re.compile(
    r"(?i)(\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|token|secret|password)\b\s*[:=]\s*)([^\s,;\"']{8,})"
)
_INLINE_SECRET_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"\bsk-[A-Za-z0-9][A-Za-z0-9_-]{12,}\b"), "[REDACTED_SK_KEY]"),
    (re.compile(r"\bAIza[0-9A-Za-z\-_]{16,}\b"), "[REDACTED_API_KEY]"),
    (re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,})\b"), "[REDACTED_TOKEN]"),
)


def now_iso() -> str:
    return datetime.now(JST).isoformat(timespec="seconds")


def _json_dump(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _json_load(value: Any, default: Any) -> Any:
    if value is None or value == "":
        return default
    if isinstance(value, (dict, list)):
        return value
    return json.loads(value)


def _strip_ansi_text(value: Optional[str]) -> str:
    if not value:
        return ""
    return _ANSI_ESCAPE_RE.sub("", value).strip()


def _redact_secret_text(value: str) -> str:
    redacted = _LABELED_SECRET_RE.sub(r"\1[REDACTED]", value)
    for pattern, replacement in _INLINE_SECRET_PATTERNS:
        redacted = pattern.sub(replacement, redacted)
    return redacted


def _subprocess_output_excerpt(value: Optional[str], limit: int = 500) -> str:
    excerpt = _redact_secret_text(_strip_ansi_text(value))
    if len(excerpt) <= limit:
        return excerpt
    return excerpt[: limit - 3].rstrip() + "..."


_tx_local = threading.local()


class ChorusStore:
    _ID_SOURCES = {
        "agent": ("agent_presets", "agent_id"),
        "room": ("chat_rooms", "room_id"),
        "part": ("chat_participants", "participant_id"),
        "msg": ("messages", "message_id"),
        "msgrec": ("message_recipients", "message_recipient_id"),
        "event": ("room_events", "event_id"),
        "route": ("routing_decisions", "routing_id"),
        "task": ("tasks", "task_id"),
        "lease": ("worker_leases", "lease_id"),
        "run": ("worker_runs", "run_id"),
        "tok": ("provider_tokens", "token_id"),
        "ufile": ("uploaded_files", "file_id"),
        "mr": ("model_registry", "model_id"),
        "cancellog": ("generation_cancel_log", "log_id"),
    }

    def __init__(self):
        self._db = get_db_instance()
        self._sq = get_sqloader_instance()
        self._counters: dict[tuple[str, str], int] = {}
        if self._db and self._sq:
            self.seed_defaults()

    # ── transaction ──────────────────────────────────────────────────────

    @contextmanager
    def transaction(self) -> Iterator["ChorusStore"]:
        if getattr(_tx_local, "txn", None) is not None:
            yield self
            return
        with self._db.begin_transaction() as txn:
            _tx_local.txn = txn
            try:
                yield self
            finally:
                _tx_local.txn = None

    # ── internal helpers ─────────────────────────────────────────────────

    def _execute(self, sql: str, params=None) -> None:
        txn = getattr(_tx_local, "txn", None)
        if txn:
            txn.execute(sql, params)
        else:
            self._db.execute(sql, params)

    def _fetch_one(self, sql: str, params=None) -> Optional[dict]:
        txn = getattr(_tx_local, "txn", None)
        if txn:
            txn.execute(sql, params)
            return txn.fetch_one()
        return self._db.fetch_one(sql, params)

    def _fetch_all(self, sql: str, params=None) -> list[dict]:
        txn = getattr(_tx_local, "txn", None)
        if txn:
            txn.execute(sql, params)
            return txn.fetch_all()
        return self._db.fetch_all(sql, params)

    def _sql(self, key: str) -> str:
        sql = self._sq.load_sql("chorus", key)
        # load_sql returns raw SQL; convert %s → ? for SQLite
        if hasattr(self._sq, "_convert_placeholder"):
            return self._sq._convert_placeholder(sql)
        return sql.replace("%s", "?")

    # ── ID generation ────────────────────────────────────────────────────

    def next_id(self, prefix: str) -> str:
        stamp = datetime.now(JST).strftime("%Y%m%d")
        key = (prefix, stamp)
        if key not in self._counters:
            self._counters[key] = self._max_sequence(prefix, stamp)
        self._counters[key] += 1
        return f"{prefix}_{stamp}_{self._counters[key]:06d}"

    def _max_sequence(self, prefix: str, stamp: str) -> int:
        source = self._ID_SOURCES.get(prefix)
        if source is None:
            return 0
        table, column = source
        sql = (
            f"SELECT {column} AS item_id FROM {table}"
            f" WHERE {column} LIKE ? ORDER BY {column} DESC LIMIT 1"
        )
        row = self._fetch_one(sql, [f"{prefix}_{stamp}_%"])
        if row is None:
            return 0
        match = re.search(r"_(\d{6})$", row["item_id"])
        return int(match.group(1)) if match else 0

    # ── seed ─────────────────────────────────────────────────────────────

    def seed_defaults(self) -> None:
        created_at = now_iso()
        models = [
            ("model_copilot_gpt_5_mini", "copilot", "gpt-5-mini", "0급", 1, 1, 1, 100),
            ("model_copilot_gpt_54_mini", "copilot", "gpt-5.4-mini", "0.33급", 1, 1, 2, 100),
            ("model_copilot_gpt_54", "copilot", "gpt-5.4", "1급", 1, 0, 4, 90),
            ("model_claude_sonnet_46", "copilot", "claude-sonnet-4.6", "1급", 1, 0, 5, 80),
            ("model_claude_runner_sonnet_46", "claude", "claude-sonnet-4-6", "1급", 1, 0, 5, 80),
            ("model_claude_haiku_45", "claude", "claude-haiku-4.5", "0.33급", 1, 1, 1, 100),
            ("model_codex_runner_gpt55", "codex", "gpt-5.5", "1급", 1, 0, 6, 70),
            ("model_codex_gpt_54_mini", "codex", "gpt-5.4-mini", "0.33급", 1, 1, 2, 100),
            ("model_codex_gpt_53_codex", "codex", "gpt-5.3-codex", "1급", 1, 0, 5, 90),
            ("model_codex_gpt_54", "codex", "gpt-5.4", "1급", 1, 0, 4, 90),
            ("model_gemini_runner_31_pro", "gemini", "gemini-3.1-pro-preview", "1급", 1, 0, 6, 60),
            ("model_gemini_3_flash", "gemini", "gemini-3-flash-preview", "0.33급", 1, 1, 2, 100),
            ("model_gemini_31_flash_lite", "gemini", "gemini-3.1-flash-lite-preview", "0.33급", 1, 0, 2, 100),
        ]
        agents = [
            ("agent_architect_001", "Architect", "architecture", "0.33급"),
            ("agent_reviewer_001", "Reviewer", "review", "1급"),
            ("agent_drafter_001", "Drafter", "draft", "0급"),
        ]
        with self.transaction():
            seed_model_sql = self._sql("seed_model")
            for m in models:
                self._execute(seed_model_sql, [*m, created_at, created_at])
            seed_agent_sql = self._sql("seed_agent")
            for agent_id, display_name, role_name, grade in agents:
                self._execute(
                    seed_agent_sql,
                    [
                        agent_id,
                        display_name,
                        role_name,
                        f"Seed {display_name} preset for Chorus prototype.",
                        "gpt-5-mini" if grade == "0급" else "gpt-5.4-mini",
                        grade,
                        _json_dump({}),
                        created_at,
                        created_at,
                    ],
                )

    # ── agent_presets ─────────────────────────────────────────────────────

    def _agent_from_row(self, row: Optional[dict]) -> Optional[dict]:
        if row is None:
            return None
        row["settings_json"] = _json_load(row.get("settings_json"), {})
        return row

    def insert_agent(self, agent: dict) -> dict:
        self._execute(
            self._sql("insert_agent"),
            [
                agent["agent_id"],
                agent["owner_user_id"],
                agent["display_name"],
                agent["role_name"],
                agent.get("description"),
                agent["default_runner"],
                agent["default_model"],
                agent["default_grade"],
                agent["system_prompt"],
                agent.get("pinned_context"),
                _json_dump(agent.get("settings_json", {})),
                agent["status"],
                agent["created_at"],
                agent["updated_at"],
            ],
        )
        return self.get_agent(agent["agent_id"])

    def list_agents(self, owner_user_id: Optional[str] = None, status: Optional[str] = "active") -> list[dict]:
        if owner_user_id and status:
            rows = self._fetch_all(self._sql("list_agents_by_owner_status"), [owner_user_id, status])
        elif owner_user_id:
            rows = self._fetch_all(self._sql("list_agents_by_owner"), [owner_user_id])
        elif status:
            rows = self._fetch_all(self._sql("list_agents_by_status"), [status])
        else:
            rows = self._fetch_all(self._sql("list_agents"))
        return [self._agent_from_row(row) for row in rows]

    def get_agent(self, agent_id: str) -> Optional[dict]:
        row = self._fetch_one(self._sql("get_agent"), [agent_id])
        return self._agent_from_row(row)

    def update_agent(self, agent_id: str, updates: dict) -> Optional[dict]:
        allowed = {
            "display_name", "role_name", "description", "default_runner",
            "default_model", "default_grade", "system_prompt", "pinned_context",
            "settings_json", "status", "updated_at",
        }
        sets: list[str] = []
        values: list[Any] = []
        for key, value in updates.items():
            if key not in allowed:
                continue
            sets.append(f"{key} = ?")
            values.append(_json_dump(value) if key == "settings_json" else value)
        if sets:
            values.append(agent_id)
            self._execute(f"UPDATE agent_presets SET {', '.join(sets)} WHERE agent_id = ?", values)
        return self.get_agent(agent_id)

    # ── chat_rooms ────────────────────────────────────────────────────────

    def insert_room(self, room: dict) -> dict:
        self._execute(
            self._sql("insert_room"),
            [
                room["room_id"],
                room["owner_user_id"],
                room["title"],
                room["mode"],
                room["status"],
                room["active_history_mode"],
                room.get("base_summary_message_id"),
                room["created_at"],
                room["updated_at"],
                room.get("archived_at"),
            ],
        )
        return self.get_room(room["room_id"])

    def get_room(self, room_id: str) -> Optional[dict]:
        return self._fetch_one(self._sql("get_room"), [room_id])

    def list_rooms(self, owner_user_id: Optional[str] = None) -> list[dict]:
        if owner_user_id:
            return self._fetch_all(self._sql("list_rooms_by_owner"), [owner_user_id])
        return self._fetch_all(self._sql("list_rooms"))

    def delete_room(self, room_id: str) -> None:
        self._execute(
            "UPDATE chat_rooms SET status = 'deleted' WHERE room_id = ?",
            [room_id],
        )

    # ── chat_participants ─────────────────────────────────────────────────

    def insert_participant(self, participant: dict) -> dict:
        self._execute(
            self._sql("insert_participant"),
            [
                participant["participant_id"],
                participant["room_id"],
                participant["participant_type"],
                participant.get("user_id"),
                participant.get("agent_id"),
                participant["display_name"],
                participant["status"],
                participant["joined_at"],
                participant.get("left_at"),
            ],
        )
        return self.get_participant(participant["participant_id"])

    def get_participant(self, participant_id: str) -> Optional[dict]:
        return self._fetch_one(self._sql("get_participant"), [participant_id])

    def list_participants(self, room_id: str, active_only: bool = False) -> list[dict]:
        if active_only:
            return self._fetch_all(self._sql("list_participants_active"), [room_id])
        return self._fetch_all(self._sql("list_participants"), [room_id])

    def update_participant(self, participant_id: str, updates: dict) -> Optional[dict]:
        allowed = {"display_name", "status", "left_at"}
        sets: list[str] = []
        values: list[Any] = []
        for key, value in updates.items():
            if key in allowed:
                sets.append(f"{key} = ?")
                values.append(value)
        if sets:
            values.append(participant_id)
            self._execute(f"UPDATE chat_participants SET {', '.join(sets)} WHERE participant_id = ?", values)
        return self.get_participant(participant_id)

    # ── room_events ───────────────────────────────────────────────────────

    def insert_room_event(self, event: dict) -> dict:
        self._execute(
            self._sql("insert_room_event"),
            [
                event["event_id"],
                event["room_id"],
                event["event_type"],
                event.get("actor_user_id"),
                event.get("actor_agent_id"),
                _json_dump(event.get("payload_json", {})),
                event["text"],
                event["created_at"],
            ],
        )
        row = self._fetch_one(self._sql("get_room_event"), [event["event_id"]])
        if row:
            row["payload_json"] = _json_load(row["payload_json"], {})
        return row

    # ── messages ──────────────────────────────────────────────────────────

    def _message_from_row(self, row: Optional[dict]) -> Optional[dict]:
        if row is None:
            return None
        row["recipient_agent_ids"] = self.list_message_recipient_agent_ids(row["message_id"])
        row.pop("replaced_by_message_id", None)
        row.pop("token_estimate", None)
        return row

    def insert_message(self, message: dict) -> dict:
        self._execute(
            self._sql("insert_message"),
            [
                message["message_id"],
                message["room_id"],
                message["sender_type"],
                message.get("sender_user_id"),
                message.get("sender_agent_id"),
                message["visibility"],
                message["content_type"],
                message["text"],
                message["delivery_mode"],
                message["history_state"],
                message.get("replaced_by_message_id"),
                message.get("source_task_id"),
                message.get("token_estimate"),
                message["created_at"],
            ],
        )
        self._execute(
            "UPDATE chat_rooms SET updated_at = ? WHERE room_id = ?",
            [message["created_at"], message["room_id"]],
        )
        return self.get_message(message["message_id"])

    def get_message(self, message_id: str) -> Optional[dict]:
        row = self._fetch_one(self._sql("get_message"), [message_id])
        return self._message_from_row(row)

    def list_messages(self, room_id: str) -> list[dict]:
        rows = self._fetch_all(self._sql("list_messages"), [room_id])
        return [self._message_from_row(row) for row in rows]

    def mark_message_cancelled(self, message_id: str) -> None:
        self._execute(
            "UPDATE messages SET is_cancelled = 1 WHERE message_id = ?",
            [message_id],
        )

    # ── message_recipients ────────────────────────────────────────────────

    def insert_message_recipient(self, recipient: dict) -> dict:
        self._execute(
            self._sql("insert_message_recipient"),
            [
                recipient["message_recipient_id"],
                recipient["message_id"],
                recipient["recipient_type"],
                recipient.get("recipient_user_id"),
                recipient.get("recipient_agent_id"),
                recipient["created_at"],
            ],
        )
        return self._fetch_one(self._sql("get_message_recipient"), [recipient["message_recipient_id"]])

    def list_message_recipients(self, message_id: str) -> list[dict]:
        return self._fetch_all(self._sql("list_message_recipients"), [message_id])

    def list_message_recipient_agent_ids(self, message_id: str) -> list[str]:
        rows = self._fetch_all(self._sql("list_message_recipient_agent_ids"), [message_id])
        return [row["recipient_agent_id"] for row in rows]

    # ── model_registry ────────────────────────────────────────────────────

    def _model_from_row(self, row: Optional[dict]) -> Optional[dict]:
        if row is None:
            return None
        row["is_active"] = bool(row["is_active"])
        row["is_default"] = bool(row.get("is_default", 0))
        row["provider_options_json"] = _json_load(row.get("provider_options_json"), None)
        return row

    def list_models(self, active_only: bool = False) -> list[dict]:
        if active_only:
            rows = self._fetch_all(self._sql("list_models_active"))
        else:
            rows = self._fetch_all(self._sql("list_models"))
        return [self._model_from_row(row) for row in rows]

    def list_models_filtered(self, runner: Optional[str] = None, active_only: bool = False) -> list[dict]:
        if runner is not None:
            base = "SELECT * FROM model_registry WHERE runner = ?"
            if active_only:
                base += " AND is_active = 1"
            base += " ORDER BY priority DESC, estimated_cost_rank"
            rows = self._fetch_all(base, [runner])
        elif active_only:
            rows = self._fetch_all(self._sql("list_models_active"))
        else:
            rows = self._fetch_all(self._sql("list_models"))
        return [self._model_from_row(row) for row in rows]

    def get_model(self, model_id: str) -> Optional[dict]:
        row = self._fetch_one(self._sql("get_model"), [model_id])
        return self._model_from_row(row)

    def insert_model(self, data: dict) -> dict:
        existing = self._fetch_one(
            "SELECT model_id FROM model_registry WHERE runner = ? AND model_name = ?",
            [data["runner"], data["model_name"]],
        )
        if existing:
            raise HTTPException(
                status_code=409,
                detail={
                    "error": "model already exists",
                    "detail": f"runner={data['runner']}, model_name={data['model_name']}",
                },
            )
        model_id = self.next_id("mr")
        now = now_iso()
        provider_json = (
            _json_dump(data["provider_options_json"])
            if data.get("provider_options_json") is not None
            else None
        )
        with self.transaction():
            if data.get("is_default"):
                self._execute(
                    "UPDATE model_registry SET is_default = 0, updated_at = ? WHERE runner = ? AND is_default = 1",
                    [now, data["runner"]],
                )
            self._execute(
                self._sql("insert_model"),
                [
                    model_id,
                    data["runner"],
                    data["model_name"],
                    data["grade"],
                    1,
                    1 if data.get("is_default") else 0,
                    data["estimated_cost_rank"],
                    data.get("priority", 0),
                    data.get("max_context_tokens"),
                    provider_json,
                    now,
                    now,
                ],
            )
        return self.get_model(model_id)

    def update_model_registry(self, model_id: str, updates: dict) -> dict:
        row = self.get_model(model_id)
        if row is None:
            raise HTTPException(status_code=404, detail={"error": "model not found"})
        warning = None
        now = now_iso()
        _ALLOWED = {
            "grade", "is_active", "is_default",
            "estimated_cost_rank", "priority",
            "max_context_tokens", "provider_options_json",
        }
        sets: list[str] = []
        values: list[Any] = []
        for key, value in updates.items():
            if key not in _ALLOWED:
                continue
            if key == "provider_options_json":
                values.append(_json_dump(value) if value is not None else None)
            elif key in ("is_active", "is_default"):
                values.append(1 if value else 0)
            else:
                values.append(value)
            sets.append(f"{key} = ?")
        if updates.get("is_active") is False:
            agents_using = self._fetch_all(
                self._sql("list_agents_using_model"),
                [row["runner"], row["model_name"]],
            )
            if agents_using:
                names = ", ".join(a["display_name"] for a in agents_using)
                warning = f"{len(agents_using)} agent preset(s) are using this model: [{names}]"
        with self.transaction():
            if updates.get("is_default"):
                self._execute(
                    "UPDATE model_registry SET is_default = 0, updated_at = ? WHERE runner = ? AND is_default = 1",
                    [now, row["runner"]],
                )
            if sets:
                sets.append("updated_at = ?")
                values.append(now)
                values.append(model_id)
                self._execute(
                    f"UPDATE model_registry SET {', '.join(sets)} WHERE model_id = ?",
                    values,
                )
        result = self.get_model(model_id)
        if warning:
            result["warning"] = warning
        return result

    def rename_model(self, model_id: str, new_name: str) -> dict:
        row = self.get_model(model_id)
        if row is None:
            raise HTTPException(status_code=404, detail={"error": "model not found"})
        if not new_name:
            raise HTTPException(status_code=422, detail={"error": "model_name cannot be empty"})
        existing = self._fetch_one(
            "SELECT model_id FROM model_registry WHERE runner = ? AND model_name = ?",
            [row["runner"], new_name],
        )
        if existing:
            raise HTTPException(
                status_code=409,
                detail={
                    "error": "model name already exists for this runner",
                    "detail": f"runner={row['runner']}, model_name={new_name}",
                },
            )
        now = now_iso()
        self._execute(
            "UPDATE model_registry SET model_name = ?, updated_at = ? WHERE model_id = ?",
            [new_name, now, model_id],
        )
        return self.get_model(model_id)

    def delete_model(self, model_id: str) -> None:
        row = self.get_model(model_id)
        if row is None:
            raise HTTPException(status_code=404, detail={"error": "model not found"})
        if row.get("is_default"):
            raise HTTPException(
                status_code=400,
                detail={"error": "Cannot delete default model"},
            )
        self._execute(
            "DELETE FROM model_registry WHERE model_id = ?",
            [model_id],
        )

    def _routing_from_row(self, row: Optional[dict]) -> Optional[dict]:
        if row is None:
            return None
        row["requires_review"] = bool(row["requires_review"])
        return row

    def insert_routing_decision(self, decision: dict) -> dict:
        self._execute(
            self._sql("insert_routing_decision"),
            [
                decision["routing_id"],
                decision["request_id"],
                decision["source"],
                decision.get("room_id"),
                decision.get("message_id"),
                decision.get("task_id"),
                decision.get("agent_id"),
                decision["task_intent"],
                decision["risk_score"],
                decision["complexity_score"],
                decision["confidence"],
                decision.get("selected_runner"),
                decision.get("selected_model"),
                decision.get("selected_grade"),
                decision["decision"],
                decision["reason_code"],
                decision["reason_text"],
                int(bool(decision["requires_review"])),
                decision.get("escalation_target"),
                decision["created_at"],
            ],
        )
        row = self._fetch_one(self._sql("get_routing_decision"), [decision["routing_id"]])
        return self._routing_from_row(row)

    # ── tasks ─────────────────────────────────────────────────────────────

    def _task_from_row(self, row: Optional[dict]) -> Optional[dict]:
        if row is None:
            return None
        row["input_json"] = _json_load(row["input_json"], {})
        row["constraints_json"] = _json_load(row["constraints_json"], {})
        row["result_json"] = _json_load(row["result_json"], None)
        # generation cancel columns may be absent in older rows
        for col in ("generation_id", "room_id", "source_message_id", "cancelled_at", "cancel_requested_at"):
            row.setdefault(col, None)
        return row

    def insert_task(self, task: dict) -> dict:
        self._execute(
            self._sql("insert_task"),
            [
                task["task_id"],
                task.get("created_by_user_id"),
                task["source"],
                task["title"],
                task["task_type"],
                task["priority"],
                task["status"],
                task.get("assigned_agent_id"),
                task.get("routing_id"),
                task.get("assigned_runner"),
                task.get("assigned_model"),
                task.get("assigned_grade"),
                task["attempt"],
                task["max_attempts"],
                _json_dump(task.get("input_json", {})),
                _json_dump(task.get("constraints_json", {})),
                _json_dump(task["result_json"]) if task.get("result_json") is not None else None,
                task.get("failure_code"),
                task.get("failure_text"),
                task.get("next_run_at"),
                task.get("last_progress_at"),
                task.get("last_progress_message"),
                task["created_at"],
                task["updated_at"],
                task.get("completed_at"),
            ],
        )
        return self.get_task(task["task_id"])

    def get_task(self, task_id: str) -> Optional[dict]:
        row = self._fetch_one(self._sql("get_task"), [task_id])
        return self._task_from_row(row)

    def list_tasks(self, status: Optional[str] = None) -> list[dict]:
        if status:
            rows = self._fetch_all(self._sql("list_tasks_by_status"), [status])
        else:
            rows = self._fetch_all(self._sql("list_tasks"))
        return [self._task_from_row(row) for row in rows]

    def update_task(self, task_id: str, updates: dict) -> Optional[dict]:
        json_columns = {"input_json", "constraints_json", "result_json"}
        allowed = {
            "status", "assigned_agent_id", "routing_id", "assigned_runner",
            "assigned_model", "assigned_grade", "attempt", "max_attempts",
            "input_json", "constraints_json", "result_json", "failure_code",
            "failure_text", "next_run_at", "last_progress_at",
            "last_progress_message", "updated_at", "completed_at",
            "generation_id", "room_id", "source_message_id",
            "cancelled_at", "cancel_requested_at",
        }
        sets: list[str] = []
        values: list[Any] = []
        for key, value in updates.items():
            if key not in allowed:
                continue
            sets.append(f"{key} = ?")
            values.append(_json_dump(value) if key in json_columns and value is not None else value)
        if sets:
            values.append(task_id)
            self._execute(f"UPDATE tasks SET {', '.join(sets)} WHERE task_id = ?", values)
        return self.get_task(task_id)

    def get_task_by_generation_id(self, generation_id: str) -> Optional[dict]:
        row = self._fetch_one(
            "SELECT * FROM tasks WHERE generation_id = ?",
            [generation_id],
        )
        return self._task_from_row(row)

    def delete_agent_messages_for_task(self, task_id: str) -> int:
        """Hard-delete agent response messages persisted for a completed task.

        Removes message_recipients rows first (FK dependency), then the messages.
        Returns the number of messages deleted.
        """
        rows = self._fetch_all(
            "SELECT message_id FROM messages WHERE source_task_id = ? AND sender_type = 'agent'",
            [task_id],
        )
        if not rows:
            return 0
        message_ids = [r["message_id"] for r in rows]
        placeholders = ",".join("?" * len(message_ids))
        self._execute(
            f"DELETE FROM message_recipients WHERE message_id IN ({placeholders})",
            message_ids,
        )
        self._execute(
            f"DELETE FROM messages WHERE message_id IN ({placeholders})",
            message_ids,
        )
        return len(message_ids)

    def insert_cancel_log(self, log: dict) -> dict:
        self._execute(
            """INSERT INTO generation_cancel_log
               (log_id, generation_id, task_id, room_id, requested_by_user_id,
                request_source, result, result_detail, requested_at, processed_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            [
                log["log_id"],
                log["generation_id"],
                log["task_id"],
                log["room_id"],
                log.get("requested_by_user_id"),
                log["request_source"],
                log["result"],
                log.get("result_detail"),
                log["requested_at"],
                log.get("processed_at"),
            ],
        )
        return log

    # ── worker_leases ─────────────────────────────────────────────────────

    def insert_lease(self, lease: dict) -> dict:
        self._execute(
            self._sql("insert_lease"),
            [
                lease["lease_id"],
                lease["task_id"],
                lease["job_id"],
                lease["worker_id"],
                lease["status"],
                lease["acquired_at"],
                lease["expires_at"],
                lease.get("released_at"),
                lease["trace_id"],
            ],
        )
        return self.get_lease(lease["lease_id"])

    def get_lease(self, lease_id: str) -> Optional[dict]:
        return self._fetch_one(self._sql("get_lease"), [lease_id])

    def list_active_leases_for_task(self, task_id: str) -> list[dict]:
        return self._fetch_all(self._sql("list_active_leases"), [task_id])

    def update_lease(self, lease_id: str, updates: dict) -> Optional[dict]:
        allowed = {"status", "expires_at", "released_at"}
        sets: list[str] = []
        values: list[Any] = []
        for key, value in updates.items():
            if key in allowed:
                sets.append(f"{key} = ?")
                values.append(value)
        if sets:
            values.append(lease_id)
            self._execute(f"UPDATE worker_leases SET {', '.join(sets)} WHERE lease_id = ?", values)
        return self.get_lease(lease_id)

    def delete_leases_by_worker(self, worker_id: str) -> int:
        """Bulk-deletes stale leases left by a specific worker on server restart."""
        self._execute(
            "DELETE FROM worker_leases WHERE worker_id = ?",
            [worker_id],
        )
        return 0

    # ── worker_runs ───────────────────────────────────────────────────────

    def _run_from_row(self, row: Optional[dict]) -> Optional[dict]:
        if row is None:
            return None
        row["artifact_paths_json"] = _json_load(row["artifact_paths_json"], [])
        return row

    def insert_worker_run(self, run: dict) -> dict:
        self._execute(
            self._sql("insert_worker_run"),
            [
                run["run_id"],
                run["task_id"],
                run.get("lease_id"),
                run["worker_id"],
                run["runner"],
                run["model"],
                run["grade"],
                run["attempt"],
                run["result_status"],
                run.get("summary"),
                _json_dump(run.get("artifact_paths_json", [])),
                run.get("log_path"),
                run.get("failure_code"),
                run.get("failure_text"),
                run["started_at"],
                run.get("finished_at"),
            ],
        )
        row = self._fetch_one(self._sql("get_worker_run"), [run["run_id"]])
        return self._run_from_row(row)

    # ── provider_tokens ───────────────────────────────────────────────────

    def insert_token(self, token: dict) -> dict:
        self._execute(
            self._sql("insert_token"),
            [
                token["token_id"],
                token["owner_user_id"],
                token["alias"],
                token["provider"],
                token["token_value"],
                token.get("status", "active"),
                token["created_at"],
                token["updated_at"],
            ],
        )
        return self.get_token(token["token_id"])

    def get_token(self, token_id: str) -> Optional[dict]:
        return self._fetch_one(self._sql("get_token"), [token_id])

    def list_tokens(self, owner_user_id: Optional[str] = None) -> list[dict]:
        if owner_user_id:
            return self._fetch_all(self._sql("list_tokens_by_owner"), [owner_user_id])
        return self._fetch_all(self._sql("list_tokens"))

    def update_token(self, token_id: str, updates: dict) -> Optional[dict]:
        allowed = {"alias", "provider", "token_value", "status", "updated_at"}
        sets: list[str] = []
        values: list[Any] = []
        for key, value in updates.items():
            if key in allowed:
                sets.append(f"{key} = ?")
                values.append(value)
        if sets:
            values.append(token_id)
            self._execute(f"UPDATE provider_tokens SET {', '.join(sets)} WHERE token_id = ?", values)
        return self.get_token(token_id)

    # ── uploaded_files ────────────────────────────────────────────────────

    def insert_uploaded_file(self, record: dict) -> dict:
        self._execute(
            self._sql("insert_uploaded_file"),
            [
                record["file_id"],
                record["owner_user_id"],
                record["original_name"],
                record["stored_path"],
                record["size_bytes"],
                record.get("mime_type"),
                record.get("status", "active"),
                record.get("expires_at"),
                record["created_at"],
            ],
        )
        return self.get_uploaded_file(record["file_id"])

    def get_uploaded_file(self, file_id: str) -> Optional[dict]:
        return self._fetch_one(self._sql("get_uploaded_file"), [file_id])

    def update_uploaded_file(self, file_id: str, updates: dict) -> Optional[dict]:
        allowed = {"status", "expires_at"}
        sets: list[str] = []
        values: list[Any] = []
        for key, value in updates.items():
            if key in allowed:
                sets.append(f"{key} = ?")
                values.append(value)
        if sets:
            values.append(file_id)
            self._execute(f"UPDATE uploaded_files SET {', '.join(sets)} WHERE file_id = ?", values)
        return self.get_uploaded_file(file_id)

    # ── context helpers ───────────────────────────────────────────────────

    def list_last_n_messages(
        self,
        room_id: str,
        n: int,
        exclude_message_id: Optional[str] = None,
    ) -> list[dict]:
        if exclude_message_id:
            rows = self._fetch_all(self._sql("list_last_n_messages_excl"), [room_id, exclude_message_id, n])
        else:
            rows = self._fetch_all(self._sql("list_last_n_messages"), [room_id, n])
        return [self._message_from_row(row) for row in rows]


STORE = ChorusStore()


# ── public API ────────────────────────────────────────────────────────────────


def create_agent(data: dict) -> dict:
    with STORE.transaction():
        agent_id = STORE.next_id("agent")
        created_at = now_iso()
        agent = {
            "agent_id": agent_id,
            "status": "active",
            "created_at": created_at,
            "updated_at": created_at,
            **data,
        }
        return STORE.insert_agent(agent)


def list_agents(owner_user_id: Optional[str] = None, status: Optional[str] = "active") -> List[dict]:
    return STORE.list_agents(owner_user_id=owner_user_id, status=status)


def get_agent(agent_id: str) -> dict:
    agent = STORE.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="AGENT_NOT_FOUND")
    return agent


def update_agent(agent_id: str, updates: dict) -> dict:
    with STORE.transaction():
        get_agent(agent_id)
        clean_updates = {key: value for key, value in updates.items() if value is not None}
        clean_updates["updated_at"] = now_iso()
        agent = STORE.update_agent(agent_id, clean_updates)
        if not agent:
            raise HTTPException(status_code=404, detail="AGENT_NOT_FOUND")
        return agent


def _room_participants(room_id: str, active_only: bool = False) -> List[dict]:
    return STORE.list_participants(room_id, active_only=active_only)


def create_room(user_id: str, title: str, mode: str, initial_agent_ids: List[str]) -> tuple[dict, List[dict]]:
    with STORE.transaction():
        room_id = STORE.next_id("room")
        created_at = now_iso()
        room = STORE.insert_room(
            {
                "room_id": room_id,
                "owner_user_id": user_id,
                "title": title,
                "mode": mode,
                "status": "active",
                "active_history_mode": "raw",
                "base_summary_message_id": None,
                "created_at": created_at,
                "updated_at": created_at,
                "archived_at": None,
            }
        )
        STORE.insert_participant(
            {
                "participant_id": STORE.next_id("part"),
                "room_id": room_id,
                "participant_type": "user",
                "user_id": user_id,
                "agent_id": None,
                "display_name": user_id,
                "status": "active",
                "joined_at": created_at,
                "left_at": None,
            }
        )
        for agent_id in initial_agent_ids:
            _invite_agent_unlocked(room_id, agent_id, user_id)
        return room, _room_participants(room_id)


def get_room(room_id: str) -> dict:
    room = STORE.get_room(room_id)
    if not room:
        raise HTTPException(status_code=404, detail="ROOM_NOT_FOUND")
    return room


def list_rooms(owner_user_id: Optional[str] = None) -> List[dict]:
    return STORE.list_rooms(owner_user_id)


def delete_room(room_id: str) -> None:
    STORE.delete_room(room_id)


def _invite_agent_unlocked(room_id: str, agent_id: str, actor_user_id: str) -> dict:
    agent = get_agent(agent_id)
    if agent["status"] != "active":
        raise HTTPException(status_code=400, detail="AGENT_INACTIVE")
    for participant in _room_participants(room_id):
        if participant["agent_id"] == agent_id:
            if participant["status"] == "inactive":
                participant = STORE.update_participant(
                    participant["participant_id"],
                    {"status": "active", "left_at": None},
                )
            return participant
    participant = STORE.insert_participant(
        {
            "participant_id": STORE.next_id("part"),
            "room_id": room_id,
            "participant_type": "agent",
            "user_id": None,
            "agent_id": agent_id,
            "display_name": agent["display_name"],
            "status": "active",
            "joined_at": now_iso(),
            "left_at": None,
        }
    )
    STORE.insert_room_event(
        {
            "event_id": STORE.next_id("event"),
            "room_id": room_id,
            "event_type": "agent_invited",
            "actor_user_id": actor_user_id,
            "actor_agent_id": None,
            "payload_json": {"agent_id": agent_id},
            "text": f"{agent['display_name']} has been invited.",
            "created_at": now_iso(),
        }
    )
    return participant


def invite_agent(room_id: str, agent_id: str, actor_user_id: str) -> dict:
    with STORE.transaction():
        get_room(room_id)
        return _invite_agent_unlocked(room_id, agent_id, actor_user_id)


def remove_agent(room_id: str, agent_id: str, actor_user_id: str) -> dict:
    with STORE.transaction():
        get_room(room_id)
        for participant in _room_participants(room_id):
            if participant["agent_id"] == agent_id and participant["status"] == "active":
                updated = STORE.update_participant(
                    participant["participant_id"],
                    {"status": "inactive", "left_at": now_iso()},
                )
                STORE.insert_room_event(
                    {
                        "event_id": STORE.next_id("event"),
                        "room_id": room_id,
                        "event_type": "agent_removed",
                        "actor_user_id": actor_user_id,
                        "actor_agent_id": None,
                        "payload_json": {"agent_id": agent_id},
                        "text": f"{participant['display_name']} has been removed.",
                        "created_at": now_iso(),
                    }
                )
                return updated
        raise HTTPException(status_code=404, detail="PARTICIPANT_NOT_FOUND")


def send_message(room_id: str, payload: dict) -> tuple[dict, List[dict]]:
    logger.debug(f"[send_message] enter — room_id={room_id!r} delivery_mode={payload.get('delivery_mode')!r} visibility={payload.get('visibility')!r}")
    from modules.worker_loop import create_agent_response_task

    with STORE.transaction():
        get_room(room_id)
        recipients = payload.get("recipient_agent_ids", [])
        if payload["visibility"] == "whisper":
            active_agent_ids = {
                participant["agent_id"]
                for participant in _room_participants(room_id, active_only=True)
                if participant["participant_type"] == "agent"
            }
            missing = [agent_id for agent_id in recipients if agent_id not in active_agent_ids]
            if missing:
                raise HTTPException(status_code=400, detail={"code": "RECIPIENT_NOT_IN_ROOM", "agent_ids": missing})

        sender = payload["sender"]
        created_at = now_iso()
        message = STORE.insert_message(
            {
                "message_id": STORE.next_id("msg"),
                "room_id": room_id,
                "sender_type": sender["sender_type"],
                "sender_user_id": sender.get("user_id"),
                "sender_agent_id": sender.get("agent_id"),
                "visibility": payload["visibility"],
                "recipient_agent_ids": recipients,
                "content_type": payload["content"]["content_type"],
                "text": payload["content"]["text"],
                "delivery_mode": payload["delivery_mode"],
                "history_state": "active" if payload["delivery_mode"] == "append_history" else "excluded",
                "source_task_id": None,
                "created_at": created_at,
            }
        )

        if message["visibility"] == "whisper":
            for agent_id in recipients:
                STORE.insert_message_recipient(
                    {
                        "message_recipient_id": STORE.next_id("msgrec"),
                        "message_id": message["message_id"],
                        "recipient_type": "agent",
                        "recipient_agent_id": agent_id,
                        "recipient_user_id": None,
                        "created_at": created_at,
                    }
                )
            if sender.get("user_id"):
                STORE.insert_message_recipient(
                    {
                        "message_recipient_id": STORE.next_id("msgrec"),
                        "message_id": message["message_id"],
                        "recipient_type": "user",
                        "recipient_user_id": sender["user_id"],
                        "recipient_agent_id": None,
                        "created_at": created_at,
                    }
                )
            message = STORE.get_message(message["message_id"])

        target_agent_ids = recipients if payload["visibility"] == "whisper" else [
            participant["agent_id"]
            for participant in _room_participants(room_id, active_only=True)
            if participant["participant_type"] == "agent"
        ]

        context_messages: list[dict] = []
        context_mode = (payload.get("context_mode") or "none").lower()
        if payload.get("delivery_mode") == "one_shot" and context_mode != "none":
            if context_mode == "pinned":
                pinned_id = payload.get("pinned_message_id")
                if pinned_id:
                    pinned_msg = STORE.get_message(pinned_id)
                    if pinned_msg:
                        role = "assistant" if pinned_msg.get("sender_agent_id") else "user"
                        context_messages.append({"role": role, "content": pinned_msg["text"]})
            elif context_mode == "rotation":
                rotation_n = max(1, min(9999, int(payload.get("rotation_n") or 5)))
                for pm in STORE.list_last_n_messages(room_id, rotation_n, exclude_message_id=message["message_id"]):
                    role = "assistant" if pm.get("sender_agent_id") else "user"
                    context_messages.append({"role": role, "content": pm["text"]})

        tasks = [create_agent_response_task(room_id, message, agent_id, context_messages=context_messages or None) for agent_id in target_agent_ids]
        return message, [{"task_id": task["task_id"], "agent_id": task["assigned_agent_id"], "status": task["status"], "generation_id": task.get("generation_id")} for task in tasks]


def list_visible_messages(
    room_id: str,
    viewer_user_id: Optional[str] = None,
    viewer_agent_id: Optional[str] = None,
) -> List[dict]:
    get_room(room_id)
    visible = []
    for message in STORE.list_messages(room_id):
        if message["visibility"] == "room":
            visible.append(message)
            continue
        if message.get("sender_user_id") and message["sender_user_id"] == viewer_user_id:
            visible.append(message)
            continue
        if message.get("sender_agent_id") and message["sender_agent_id"] == viewer_agent_id:
            visible.append(message)
            continue
        recipients = STORE.list_message_recipients(message["message_id"])
        if viewer_user_id and any(item.get("recipient_user_id") == viewer_user_id for item in recipients):
            visible.append(message)
            continue
        if viewer_agent_id and any(item.get("recipient_agent_id") == viewer_agent_id for item in recipients):
            visible.append(message)
    # Inject context_usage from task result_json for agent messages (no DB schema change needed).
    for message in visible:
        source_task_id = message.get("source_task_id")
        if source_task_id:
            task = STORE.get_task(source_task_id)
            if task:
                result_json = task.get("result_json") or {}
                if isinstance(result_json, str):
                    try:
                        result_json = json.loads(result_json)
                    except Exception:
                        result_json = {}
                context_usage = result_json.get("context_usage")
                if context_usage:
                    message["context_usage"] = context_usage
    return visible


def persist_agent_response_message(task: dict, result_json: dict) -> Optional[dict]:
    """
    T023: Save agent_response task result to messages table.
    
    Persists the AI response as a message when an agent_response task completes.
    Checks for duplicates using source_task_id to prevent duplicate inserts.
    
    Args:
        task: Completed task dict with input_json containing room_id, message_id, and assigned_agent_id
        result_json: Task result containing "summary" (the AI response text)
    
    Returns:
        Inserted message dict, or None if duplicate detected or inputs missing
    """
    task_id = task.get("task_id")
    has_summary = bool(result_json.get("summary"))
    logger.debug(f"[persist_agent_response_message] enter task_id={task_id} has_summary={has_summary}")
    try:
        task_input = task.get("input_json", {})
        room_id = task_input.get("room_id")
        user_message_id = task_input.get("message_id")

        if not room_id or not user_message_id:
            logger.debug(f"[persist_agent_response_message] missing room_id or message_id for task {task_id}")
            return None

        agent_response_text = result_json.get("summary", "")
        if not agent_response_text:
            logger.debug(f"[persist_agent_response_message] empty summary for task {task_id}, skipping insert")
            return None

        with STORE.transaction():
            rows = STORE._fetch_all(
                STORE._sql("list_messages"),
                [room_id]
            )
            for row in rows:
                msg = STORE._message_from_row(row)
                if msg and msg.get("source_task_id") == task["task_id"]:
                    logger.debug(f"[persist_agent_response_message] duplicate detected for task {task_id}, skipping insert")
                    return None

            created_at = now_iso()
            logger.debug(f"[persist_agent_response_message] inserting message for task {task_id} room_id={room_id}")
            agent_message = STORE.insert_message(
                {
                    "message_id": STORE.next_id("msg"),
                    "room_id": room_id,
                    "sender_type": "agent",
                    "sender_user_id": None,
                    "sender_agent_id": task.get("assigned_agent_id"),
                    "visibility": "room",
                    "content_type": "text",
                    "text": agent_response_text,
                    "delivery_mode": "append_history",
                    "history_state": "active",
                    "replaced_by_message_id": None,
                    "source_task_id": task["task_id"],
                    "token_estimate": None,
                    "created_at": created_at,
                }
            )
            logger.debug(f"[persist_agent_response_message] insert done for task {task_id} message_id={agent_message.get('message_id') if agent_message else None}")
            return agent_message
    except Exception as e:
        logger.error(f"[persist_agent_response_message] error persisting agent response for task {task_id}: {e}")
        return None


# ── T012: Agent Chat synchronous response ────────────────────────────────────


def _build_chat_history(room_id: str, exclude_message_id: str) -> List[dict]:
    """Return active room messages as OpenAI-style role/content pairs, excluding the given message."""
    rows = STORE.list_messages(room_id)
    history: List[dict] = []
    for msg in rows:
        if msg["message_id"] == exclude_message_id:
            continue
        if msg.get("history_state") != "active":
            continue
        if msg.get("visibility") != "room":
            continue
        if msg.get("is_cancelled"):
            continue
        role = "assistant" if msg.get("sender_agent_id") else "user"
        history.append({"role": role, "content": msg["text"]})
    return history


RUNNER_TOKEN_ENV: dict[str, tuple[str, str]] = {
    "gemini": ("google", "GEMINI_API_KEY"),
    "claude": ("anthropic", "ANTHROPIC_API_KEY"),
    "codex": ("openai", "OPENAI_API_KEY"),
    "copilot": ("copilot", "COPILOT_GITHUB_TOKEN"),
}


def _resolve_copilot_executable() -> str:
    resolved = shutil.which("copilot")
    if resolved and "copilotcli" not in resolved.lower():
        return resolved

    npm_copilot = os.path.expanduser(r"~\AppData\Roaming\npm\copilot.CMD")
    if os.path.exists(npm_copilot):
        if resolved:
            logger.warning(
                f"[_resolve_copilot_executable] ignoring VS Code copilotCli path: {resolved!r}; "
                f"using npm copilot: {npm_copilot!r}"
            )
        return npm_copilot

    return resolved or "copilot"


def _build_subprocess_env(runner: str, provider_token_id: Optional[str] = None) -> dict:
    env = os.environ.copy()
    
    # copilot runner의 경우 npm PATH 확인 및 추가
    if runner == "copilot":
        npm_bin_path = os.path.expanduser(r"~\AppData\Roaming\npm")
        if npm_bin_path not in env.get("PATH", ""):
            logger.warning(f"[_build_subprocess_env] npm bin path not in PATH, adding: {npm_bin_path}")
            env["PATH"] = npm_bin_path + os.pathsep + env.get("PATH", "")
    
    if not provider_token_id:
        return env
    expected = RUNNER_TOKEN_ENV.get(runner)
    if expected is None:
        return env
    expected_provider, env_key = expected
    token = STORE.get_token(provider_token_id)
    if not token:
        raise HTTPException(status_code=400, detail={"code": "PROVIDER_TOKEN_NOT_FOUND"})
    if token.get("status") != "active":
        raise HTTPException(status_code=400, detail={"code": "PROVIDER_TOKEN_INACTIVE"})
    if token.get("provider") != expected_provider:
        raise HTTPException(
            status_code=400,
            detail={
                "code": "PROVIDER_TOKEN_MISMATCH",
                "runner": runner,
                "expected_provider": expected_provider,
                "actual_provider": token.get("provider"),
            },
        )
    env[env_key] = token["token_value"]
    return env


STREAMING_MAX_AGENTS: int = 4


def _build_ai_prompt(
    runner: str,
    system_prompt: Optional[str],
    history: List[dict],
    user_text: str,
    pinned_context: Optional[str] = None,
) -> str:
    """Build the full prompt string for AI CLI runners."""
    parts: List[str] = []
    if system_prompt:
        parts.append(system_prompt)
    if pinned_context and pinned_context.strip():
        parts.append(f"Pinned context:\n\n{pinned_context}")
    for msg in history:
        prefix = "AI" if msg["role"] == "assistant" else "User"
        parts.append(f"{prefix}: {msg['content']}")
    parts.append(f"User: {user_text}")
    return "\n\n".join(parts)


def _call_ai_streaming(
    runner: str,
    model: str,
    system_prompt: Optional[str],
    history: List[dict],
    user_text: str,
    on_chunk: "Optional[callable]" = None,
    on_thinking_chunk: "Optional[callable]" = None,
    cancel_check: "Optional[callable]" = None,
    pinned_context: Optional[str] = None,
    provider_token_id: Optional[str] = None,
    work_dir: Optional[str] = None,
    allowed_dirs: Optional[List[str]] = None,
) -> "tuple[str, Optional[dict]]":
    """
    Call AI CLI using subprocess.Popen, streaming stdout line-by-line.

    Each non-empty line read from stdout is passed to on_chunk(line).
    Returns the same (response_text, context_usage) tuple as _call_ai_sync().
    Falls back to treating the complete stdout as text for non-plaintext runners.
    """
    from modules.context_meter import compute_context_usage

    prompt = _build_ai_prompt(runner, system_prompt, history, user_text, pinned_context)
    context_usage = compute_context_usage(prompt, runner, model)
    logger.debug(
        f"[_call_ai_streaming] context_usage estimate runner={runner!r} model={model!r} "
        f"ratio={context_usage['context_ratio']} status={context_usage['context_status']!r}"
    )

    env = _build_subprocess_env(runner, provider_token_id)

    if runner == "copilot":
        import json as _json

        executable = _resolve_copilot_executable()
        
        # Handle Windows CMD/BAT files (similar to _call_ai_sync)
        if executable.upper().endswith((".CMD", ".BAT")):
            npm_basedir = os.path.dirname(executable)
            npm_loader = os.path.join(npm_basedir, "node_modules", "@github", "copilot", "npm-loader.js")
            node_exe = shutil.which("node")
            if node_exe and os.path.exists(npm_loader):
                _cmd = [node_exe, npm_loader, "--allow-all", "--model", model, "--output-format=json", "-p", "-"]
            else:
                _cmd = ["cmd", "/c", executable, "--allow-all", "--model", model, "--output-format=json", "-p", "-"]
        else:
            _cmd = [executable, "--allow-all", "--model", model, "--output-format=json", "-p", "-"]
        proc = subprocess.Popen(
            _cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            cwd=PROJECT_ROOT,
            env=env,
        )
        # Pass prompt via stdin to avoid OS command-line length limits (T108).
        proc.stdin.write(prompt)
        proc.stdin.close()

        stdout_lines = []
        _out_queue: "queue.Queue[Optional[str]]" = queue.Queue()

        def _copilot_reader() -> None:
            try:
                for _ln in iter(proc.stdout.readline, ""):
                    _out_queue.put(_ln)
            finally:
                _out_queue.put(None)  # EOF sentinel

        _reader_thread = threading.Thread(target=_copilot_reader, daemon=True)
        _reader_thread.start()

        _exit_code: int = 0
        _line_count = 0

        while True:
            try:
                raw = _out_queue.get(timeout=120)
            except queue.Empty:
                logger.warning("[_call_ai_streaming] copilot: no output for 120s, killing")
                proc.kill()
                break

            if raw is None:  # EOF — process exited
                break

            raw = raw.strip()
            if not raw:
                continue

            _line_count += 1

            # cancel check every 10 events
            if cancel_check and _line_count % 10 == 0 and cancel_check():
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                logger.info("[_call_ai_streaming] copilot: cancel requested")
                break

            try:
                event = _json.loads(raw)
            except _json.JSONDecodeError:
                # non-JSON line (e.g. ANSI, debug text) — pass as raw chunk
                stripped = _strip_ansi_text(raw)
                if stripped and on_chunk:
                    try:
                        on_chunk(stripped)
                    except Exception as _e:
                        logger.warning(f"[_call_ai_streaming] copilot on_chunk error: {_e}")
                continue

            event_type = event.get("type", "")
            data = event.get("data") or {}

            if event_type == "assistant.message_delta":
                delta = data.get("deltaContent", "")
                if delta and on_chunk:
                    try:
                        on_chunk(delta)
                    except Exception as _e:
                        logger.warning(f"[_call_ai_streaming] copilot on_chunk error: {_e}")
                if delta:
                    stdout_lines.append(delta)

            elif event_type == "assistant.reasoning_delta":
                thinking_delta = data.get("delta", "")
                if thinking_delta and on_thinking_chunk:
                    try:
                        on_thinking_chunk(thinking_delta)
                    except Exception as _e:
                        logger.warning(f"[_call_ai_streaming] copilot on_thinking_chunk error: {_e}")

            elif event_type == "assistant.message":
                # Full message event: use as authoritative fallback if no deltas arrived.
                # Both Claude and GPT emit this event before assistant.turn_end.
                _full_content = data.get("content", "")
                if _full_content and not stdout_lines:
                    stdout_lines.append(_full_content)
                    if on_chunk:
                        try:
                            on_chunk(_full_content)
                        except Exception as _e:
                            logger.warning(f"[_call_ai_streaming] copilot on_chunk error: {_e}")

            elif event_type == "assistant.turn_end":
                # Explicit completion signal for all copilot-runner models (Claude and GPT alike).
                break

            elif event_type == "result":
                _exit_code = data.get("exitCode", event.get("exitCode", 0))
                # result is the last event; loop will exit on next iteration (None sentinel)

            elif event_type in ("abort", "exception", "error"):
                logger.warning(f"[_call_ai_streaming] copilot event error: {event}")
                break

            # skip: session.*, user.message, assistant.reasoning,
            #        assistant.message_start, assistant.turn_start,
            #        assistant.tool_call, tool.*, user.tool_result

        # wait for process
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass

        # drain stderr (safe — process has exited)
        stderr_text = proc.stderr.read() if proc.stderr else ""
        result_returncode = proc.returncode if proc.returncode is not None else _exit_code

        result_stdout = "".join(stdout_lines)
        if not result_stdout:
            logger.warning(
                f"[_call_ai_streaming] copilot: empty response for model={model} returncode={result_returncode} stderr={(stderr_text or '')[:200]}"
            )
        context_usage = {}
        return result_stdout, context_usage

    elif runner == "claude":
        executable = shutil.which("claude") or "claude"
        proc = subprocess.Popen(
            [executable, "--dangerously-skip-permissions", "--model", model, "-p", "-"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            cwd=PROJECT_ROOT,
            env=env,
        )
        stdout_lines = []
        proc.stdin.write(prompt)
        proc.stdin.close()
        _line_count = 0
        _was_killed = False
        for line in proc.stdout:
            stdout_lines.append(line)
            _line_count += 1
            if cancel_check and _line_count % 5 == 0 and cancel_check():
                proc.kill()
                _was_killed = True
                logger.info("[_call_ai_streaming] claude: cancel requested, subprocess killed")
                break
            if line.strip() and on_chunk:
                try:
                    on_chunk(line.rstrip("\n"))
                except Exception as _cb_exc:
                    logger.warning(f"[_call_ai_streaming] on_chunk error: {_cb_exc}")
        if _was_killed:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        else:
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                logger.warning("[_call_ai_streaming] claude: proc.wait timed out on normal exit, continuing")
        stderr_text = proc.stderr.read() if proc.stderr else ""
        result_stdout = "".join(stdout_lines)
        result_returncode = proc.returncode
        result_stderr = stderr_text
        try:
            payload = json.loads(result_stdout)
            output = payload.get("result") or payload.get("text") or ""
            actual_usage = payload.get("usage") or {}
            total_cost_usd = payload.get("total_cost_usd")
            if actual_usage:
                context_usage["actual_input_tokens"] = actual_usage.get("input_tokens")
                context_usage["actual_output_tokens"] = actual_usage.get("output_tokens")
                context_usage["total_cost_usd"] = total_cost_usd
        except (json.JSONDecodeError, Exception):
            logger.warning(f"[_call_ai_streaming] claude JSON parse failed, using plain text runner={runner!r}")
            output = _strip_ansi_text(result_stdout)

    elif runner == "gemini":
        executable = shutil.which("gemini") or "gemini"
        proc = subprocess.Popen(
            [executable, "--model", model, "-p", "-"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            cwd=PROJECT_ROOT,
            env=env,
        )
        stdout_lines = []
        proc.stdin.write(prompt)
        proc.stdin.close()
        _line_count = 0
        _was_killed = False
        for line in proc.stdout:
            stdout_lines.append(line)
            _line_count += 1
            if cancel_check and _line_count % 5 == 0 and cancel_check():
                proc.kill()
                _was_killed = True
                logger.info("[_call_ai_streaming] gemini: cancel requested, subprocess killed")
                break
            stripped = _strip_ansi_text(line)
            if stripped and on_chunk:
                try:
                    on_chunk(stripped)
                except Exception as _cb_exc:
                    logger.warning(f"[_call_ai_streaming] on_chunk error: {_cb_exc}")
        if _was_killed:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        else:
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                logger.warning("[_call_ai_streaming] gemini: proc.wait timed out on normal exit, continuing")
        stderr_text = proc.stderr.read() if proc.stderr else ""
        result_stdout = "".join(stdout_lines)
        result_returncode = proc.returncode
        result_stderr = stderr_text
        output = _strip_ansi_text(result_stdout)

    elif runner == "codex":
        executable = shutil.which("codex") or "codex"
        _codex_work_dir = work_dir if work_dir else str(PROJECT_ROOT)
        cmd = [executable, "-C", _codex_work_dir]
        for _dir_path in (allowed_dirs or []):
            _trimmed = _dir_path.strip()
            if not _trimmed:
                continue
            cmd.extend(["--add-dir", _trimmed])
        cmd.extend([
            "--ask-for-approval", "never",
            "--sandbox", "workspace-write",
            "exec",
            "--json",
            "--model", model,
            "-",
        ])
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            cwd=PROJECT_ROOT,
            env=env,
        )
        stdout_lines = []
        proc.stdin.write(prompt)
        proc.stdin.close()
        codex_usage: Optional[dict] = None
        answer_parts: List[str] = []
        _line_count = 0
        _was_killed = False
        for line in proc.stdout:
            stdout_lines.append(line)
            _line_count += 1
            if cancel_check and _line_count % 5 == 0 and cancel_check():
                proc.kill()
                _was_killed = True
                logger.info("[_call_ai_streaming] codex: cancel requested, subprocess killed")
                break
            if not line.strip():
                continue
            try:
                _event = json.loads(line)
            except json.JSONDecodeError:
                continue
            _etype = _event.get("type", "")
            if _etype in ("thread.started", "turn.started"):
                continue
            if _etype == "turn.completed":
                codex_usage = _event.get("usage")
                break
            if _etype == "item.completed":
                _item = _event.get("item") or {}
                if isinstance(_item, dict) and _item.get("type") == "agent_message":
                    _txt = _item.get("text", "")
                    if _txt:
                        answer_parts.append(str(_txt))
                        if on_chunk:
                            try:
                                on_chunk(str(_txt))
                            except Exception as _cb_exc:
                                logger.warning(f"[_call_ai_streaming] on_chunk error: {_cb_exc}")
        if _was_killed:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        else:
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                logger.warning("[_call_ai_streaming] codex: proc.wait timed out on normal exit, continuing")
        stderr_text = proc.stderr.read() if proc.stderr else ""
        result_stdout = "".join(stdout_lines)
        result_returncode = proc.returncode
        result_stderr = stderr_text
        output = "".join(answer_parts).strip()
        if not output:
            output = _strip_ansi_text(result_stdout)
            logger.warning(
                f"[_call_ai_streaming] codex JSONL text extraction yielded nothing, "
                f"using stripped stdout fallback runner={runner!r}"
            )
        if codex_usage:
            context_usage["actual_input_tokens"] = codex_usage.get("input_tokens")
            context_usage["actual_output_tokens"] = codex_usage.get("output_tokens")

    else:
        raise HTTPException(
            status_code=501,
            detail={"code": "RUNNER_NOT_SUPPORTED", "runner": runner},
        )

    if result_returncode != 0:
        _stderr_lower = (result_stderr or "").lower()
        if any(kw in _stderr_lower for kw in ("unknown model", "model not found", "invalid model specification")):
            _error_category = "model_error"
        elif any(kw in _stderr_lower for kw in ("authentication failed", "invalid api key", "401 unauthorized")):
            _error_category = "auth_error"
        elif any(kw in _stderr_lower for kw in ("insufficient credits", "rate limit exceeded", "429 too many requests", "quota exceeded")):
            _error_category = "credit_error"
        else:
            _error_category = "unknown"
        failure_detail = {
            "code": "AI_SUBPROCESS_FAILED",
            "runner": runner,
            "model": model,
            "returncode": result_returncode,
            "stderr_excerpt": _subprocess_output_excerpt(result_stderr),
            "stdout_excerpt": _subprocess_output_excerpt(result_stdout),
            "error_category": _error_category,
        }
        logger.error(
            f"[_call_ai_streaming] subprocess failed runner={runner!r} model={model!r} "
            f"returncode={result_returncode} detail={failure_detail!r}"
        )
        raise HTTPException(status_code=502, detail=failure_detail)

    if not output:
        raise HTTPException(
            status_code=502,
            detail={"code": "AI_EMPTY_RESPONSE", "runner": runner, "model": model},
        )

    return output, context_usage


def _call_ai_sync(
    runner: str,
    model: str,
    system_prompt: Optional[str],
    history: List[dict],
    user_text: str,
    pinned_context: Optional[str] = None,
    provider_token_id: Optional[str] = None,
    work_dir: Optional[str] = None,
    allowed_dirs: Optional[List[str]] = None,
) -> tuple[str, Optional[dict]]:
    """
    Call AI CLI synchronously and return (response_text, context_usage).

    Method A (Q005 approved): subprocess CLI call.
    runner CLI (copilot/claude/gemini/codex) must be on PATH and authenticated in the server environment.

    context_usage structure:
        {
            "estimated_input_tokens": int,
            "context_window": int,
            "context_ratio": float,
            "context_status": "OK" | "WARN" | "COMPRESS_SOON" | "BLOCK_OR_COMPRESS_NOW",
            # Claude / Codex only (when CLI exposes usage):
            "actual_input_tokens": int,
            "actual_output_tokens": int,
            "total_cost_usd": float | None,
        }
    """
    from modules.context_meter import compute_context_usage

    parts: List[str] = []
    if system_prompt:
        parts.append(system_prompt)
    if pinned_context and pinned_context.strip():
        parts.append(f"Pinned context:\n\n{pinned_context}")
    for msg in history:
        prefix = "AI" if msg["role"] == "assistant" else "User"
        parts.append(f"{prefix}: {msg['content']}")
    parts.append(f"User: {user_text}")
    prompt = "\n\n".join(parts)

    context_usage = compute_context_usage(prompt, runner, model)
    logger.debug(
        f"[_call_ai_sync] context_usage estimate runner={runner!r} model={model!r} "
        f"estimated_tokens={context_usage['estimated_input_tokens']} "
        f"ratio={context_usage['context_ratio']} status={context_usage['context_status']!r}"
    )

    env = _build_subprocess_env(runner, provider_token_id)

    if runner == "copilot":
        executable = _resolve_copilot_executable()
        logger.debug(
            f"[_call_ai_sync] copilot executable resolve: "
            f"shutil.which('copilot')={shutil.which('copilot')!r}, selected={executable!r}"
        )
        if executable.upper().endswith((".CMD", ".BAT")):
            npm_basedir = os.path.dirname(executable)
            npm_loader = os.path.join(npm_basedir, "node_modules", "@github", "copilot", "npm-loader.js")
            node_exe = shutil.which("node")
            if node_exe and os.path.exists(npm_loader):
                _copilot_cmd = [node_exe, npm_loader, "--allow-all", "--model", model]
            else:
                _copilot_cmd = ["cmd", "/c", executable, "--allow-all", "--model", model]
        else:
            _copilot_cmd = [executable, "--allow-all", "--model", model]
        result = subprocess.run(
            _copilot_cmd,
            input=prompt,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=120,
            cwd=PROJECT_ROOT,
            env=env,
        )
        logger.debug(f"[_call_ai_sync] copilot result: RC={result.returncode}, stdout_len={len(result.stdout) if result.stdout else 0}, stderr_snippet={(result.stderr or '')[:200]!r}")
        output = _strip_ansi_text(result.stdout)
        # Copilot CLI does not expose machine-readable usage in stdin mode (NR028 §2.3).
        # context_usage retains the server-side estimate only.

    elif runner == "claude":
        executable = shutil.which("claude") or "claude"
        result = subprocess.run(
            [executable, "--dangerously-skip-permissions", "--model", model, "-p", "-"],
            input=prompt,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=120,
            cwd=PROJECT_ROOT,
            env=env,
        )
        try:
            payload = json.loads(result.stdout)
            output = payload.get("result") or payload.get("text") or ""
            actual_usage = payload.get("usage") or {}
            total_cost_usd = payload.get("total_cost_usd")
            if actual_usage:
                context_usage["actual_input_tokens"] = actual_usage.get("input_tokens")
                context_usage["actual_output_tokens"] = actual_usage.get("output_tokens")
                context_usage["total_cost_usd"] = total_cost_usd
        except (json.JSONDecodeError, Exception):
            # Fallback: treat stdout as plain text if JSON parsing fails.
            logger.warning(
                f"[_call_ai_sync] claude JSON parse failed, falling back to plain text runner={runner!r}"
            )
            output = _strip_ansi_text(result.stdout)

    elif runner == "gemini":
        executable = shutil.which("gemini") or "gemini"
        result = subprocess.run(
            [executable, "--model", model, "-p", "-"],
            input=prompt,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=120,
            cwd=PROJECT_ROOT,
            env=env,
        )
        output = _strip_ansi_text(result.stdout)
        # Gemini CLI usage extraction: kept as estimate-only (NR028 §2.4 / T080 §6).
        # --output-format json is not added because CLI version compatibility is unclear.

    elif runner == "codex":
        executable = shutil.which("codex") or "codex"
        _codex_work_dir = work_dir if work_dir else str(PROJECT_ROOT)
        _codex_cmd: List[str] = [executable, "-C", _codex_work_dir]
        for _dir_path in (allowed_dirs or []):
            _trimmed = _dir_path.strip()
            if not _trimmed:
                continue
            _codex_cmd.extend(["--add-dir", _trimmed])
        # Phase 2: --json produces JSONL; turn.completed.usage holds token counts (NR027/NR028).
        # NOTE(Q080): exact item.* event schema for text extraction is pending confirmation.
        # Current implementation uses the most probable structure observed in NR027/NR028.
        _codex_cmd.extend([
            "--ask-for-approval", "never",
            "--sandbox", "workspace-write",
            "exec",
            "--json",
            "--model", model,
            "-",
        ])
        result = subprocess.run(
            _codex_cmd,
            input=prompt,
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=300,
            cwd=PROJECT_ROOT,
            env=env,
        )
        codex_usage: Optional[dict] = None
        answer_parts: List[str] = []
        for _line in result.stdout.splitlines():
            if not _line.strip():
                continue
            try:
                _event = json.loads(_line)
            except json.JSONDecodeError:
                continue
            _etype = _event.get("type", "")
            if _etype in ("thread.started", "turn.started"):
                continue
            if _etype == "turn.completed":
                codex_usage = _event.get("usage")
                break
            if _etype == "item.completed":
                _item = _event.get("item") or {}
                if isinstance(_item, dict) and _item.get("type") == "agent_message":
                    _txt = _item.get("text", "")
                    if _txt:
                        answer_parts.append(str(_txt))
        output = "".join(answer_parts).strip()
        if not output:
            # Fallback: if JSONL text extraction yields nothing, use stripped stdout.
            # This handles cases where the item.* schema differs from expected.
            output = _strip_ansi_text(result.stdout)
            logger.warning(
                f"[_call_ai_sync] codex JSONL text extraction yielded nothing, "
                f"using stripped stdout fallback runner={runner!r}"
            )
        if codex_usage:
            context_usage["actual_input_tokens"] = codex_usage.get("input_tokens")
            context_usage["actual_output_tokens"] = codex_usage.get("output_tokens")

    else:
        raise HTTPException(
            status_code=501,
            detail={"code": "RUNNER_NOT_SUPPORTED", "runner": runner},
        )

    if result.returncode != 0:
        _stderr_lower = (result.stderr or "").lower()
        if any(kw in _stderr_lower for kw in ("unknown model", "model not found", "invalid model specification")):
            _error_category = "model_error"
        elif any(kw in _stderr_lower for kw in ("authentication failed", "invalid api key", "401 unauthorized")):
            _error_category = "auth_error"
        elif any(kw in _stderr_lower for kw in ("insufficient credits", "rate limit exceeded", "429 too many requests", "quota exceeded")):
            _error_category = "credit_error"
        else:
            _error_category = "unknown"
        failure_detail = {
            "code": "AI_SUBPROCESS_FAILED",
            "runner": runner,
            "model": model,
            "returncode": result.returncode,
            "stderr_excerpt": _subprocess_output_excerpt(result.stderr),
            "stdout_excerpt": _subprocess_output_excerpt(result.stdout),
            "error_category": _error_category,
        }
        logger.error(
            f"[_call_ai_sync] subprocess failed runner={runner!r} model={model!r} "
            f"returncode={result.returncode} detail={failure_detail!r}"
        )
        raise HTTPException(
            status_code=502,
            detail=failure_detail,
        )

    if not output:
        raise HTTPException(
            status_code=502,
            detail={"code": "AI_EMPTY_RESPONSE", "runner": runner, "model": model},
        )

    return output, context_usage


def send_message_sync(room_id: str, payload: dict) -> tuple[dict, List[dict]]:
    """T075: delegates to send_message() so single-agent chat uses the async agent_response task path."""
    logger.debug(f"[send_message_sync] delegating to send_message — room_id={room_id!r}")
    return send_message(room_id, payload)
