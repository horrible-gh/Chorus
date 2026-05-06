from __future__ import annotations

import json
import re
import shutil
import subprocess
import threading
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator, List, Optional

from fastapi import HTTPException

from config import get_db_instance, get_sqloader_instance

JST = timezone(timedelta(hours=9))
SERVER_DIR = Path(__file__).resolve().parents[1]
PROJECT_ROOT = Path(__file__).resolve().parents[2]


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
        return self.get_message(message["message_id"])

    def get_message(self, message_id: str) -> Optional[dict]:
        row = self._fetch_one(self._sql("get_message"), [message_id])
        return self._message_from_row(row)

    def list_messages(self, room_id: str) -> list[dict]:
        rows = self._fetch_all(self._sql("list_messages"), [room_id])
        return [self._message_from_row(row) for row in rows]

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

    # ── routing_decisions ─────────────────────────────────────────────────

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
            "text": f"{agent['display_name']}가 초대되었습니다.",
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
                        "text": f"{participant['display_name']}가 제거되었습니다.",
                        "created_at": now_iso(),
                    }
                )
                return updated
        raise HTTPException(status_code=404, detail="PARTICIPANT_NOT_FOUND")


def send_message(room_id: str, payload: dict) -> tuple[dict, List[dict]]:
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
        return message, [{"task_id": task["task_id"], "agent_id": task["assigned_agent_id"], "status": task["status"]} for task in tasks]


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
    return visible


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
        role = "assistant" if msg.get("sender_agent_id") else "user"
        history.append({"role": role, "content": msg["text"]})
    return history


def _call_ai_sync(
    runner: str,
    model: str,
    system_prompt: Optional[str],
    history: List[dict],
    user_text: str,
) -> str:
    """
    Call AI CLI synchronously and return the response text.

    Method A (Q005 approved): subprocess CLI call.
    runner CLI (copilot/claude) must be on PATH and authenticated in the server environment.
    """
    parts: List[str] = []
    if system_prompt:
        parts.append(system_prompt)
    for msg in history:
        prefix = "AI" if msg["role"] == "assistant" else "User"
        parts.append(f"{prefix}: {msg['content']}")
    parts.append(f"User: {user_text}")
    prompt = "\n\n".join(parts)

    # Strip ANSI escape codes helper
    _ansi = re.compile(r"\x1b\[[0-9;]*m")

    if runner == "copilot":
        executable = shutil.which("copilot") or "copilot"
        safe_prompt = prompt.replace('\r\n', '\n').replace('\n', ' ')
        result = subprocess.run(
            [executable, "--allow-all", "--model", model, "-p", safe_prompt],
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=120,
            cwd=PROJECT_ROOT,
        )
        output = _ansi.sub("", result.stdout).strip()

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
        )
        output = _ansi.sub("", result.stdout).strip()

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
        )
        output = _ansi.sub("", result.stdout).strip()

    else:
        raise HTTPException(
            status_code=501,
            detail={"code": "RUNNER_NOT_SUPPORTED", "runner": runner},
        )

    if result.returncode != 0:
        raise HTTPException(
            status_code=502,
            detail={
                "code": "AI_SUBPROCESS_FAILED",
                "runner": runner,
                "model": model,
                "returncode": result.returncode,
                "stderr": result.stderr.strip()[:500] if result.stderr else "",
            },
        )

    if not output:
        raise HTTPException(
            status_code=502,
            detail={"code": "AI_EMPTY_RESPONSE", "runner": runner, "model": model},
        )

    return output


def send_message_sync(room_id: str, payload: dict) -> tuple[dict, List[dict]]:
    """
    T012: message.send — public message + single agent synchronous response.

    Flow:
      1. Save user message to DB
      2. Get active agent participants (single agent only)
      3. Call T011 routing (select_model) to determine model
      4. Build conversation history for context
      5. Call AI synchronously (_call_ai_sync)
      6. Save AI response message to DB
      7. Return (user_message, task_info_list) in P001 format

    Restrictions (T012 scope): public messages only; whisper, compression,
    one_shot context modes, and Worker Loop are not used here.
    """
    from modules.routing import select_model

    # ── Phase 1: save user message and prepare routing (inside transaction) ──
    with STORE.transaction():
        get_room(room_id)

        created_at = now_iso()
        sender = payload["sender"]
        user_message = STORE.insert_message(
            {
                "message_id": STORE.next_id("msg"),
                "room_id": room_id,
                "sender_type": sender["sender_type"],
                "sender_user_id": sender.get("user_id"),
                "sender_agent_id": sender.get("agent_id"),
                "visibility": "room",
                "content_type": payload["content"]["content_type"],
                "text": payload["content"]["text"],
                "delivery_mode": payload["delivery_mode"],
                "history_state": "active",
                "replaced_by_message_id": None,
                "source_task_id": None,
                "token_estimate": None,
                "created_at": created_at,
            }
        )

        active_agents = [
            p
            for p in _room_participants(room_id, active_only=True)
            if p["participant_type"] == "agent"
        ]

        if not active_agents:
            return user_message, []

        # Single agent response (T012 scope)
        target_participant = active_agents[0]
        agent = STORE.get_agent(target_participant["agent_id"])
        if not agent:
            return user_message, []

        routing_decision = select_model(
            {
                "request_id": STORE.next_id("req"),
                "source": "agent_chat",
                "room_id": room_id,
                "message_id": user_message["message_id"],
                "agent_id": agent["agent_id"],
                "task_intent": "agent_response",
                "risk_hint": "low",
                "preferred_runner": agent.get("default_runner") or "copilot",
                "allowed_grade_min": "0급",
                "allowed_grade_max": "1급",
                "title": f"Chat response for {user_message['message_id']}",
                "instruction": payload["content"]["text"],
                "read_paths_count": 0,
                "write_paths_count": 0,
                "can_modify_code": False,
                "can_modify_index": False,
                "requires_review": False,
            }
        )

    # ── Phase 2: build history and call AI (outside transaction) ──
    history = _build_chat_history(room_id, user_message["message_id"])

    ai_text = _call_ai_sync(
        runner=routing_decision["selected_runner"],
        model=routing_decision["selected_model"],
        system_prompt=agent.get("system_prompt"),
        history=history,
        user_text=payload["content"]["text"],
    )

    # ── Phase 3: save AI response (inside transaction) ──
    with STORE.transaction():
        response_at = now_iso()
        agent_message = STORE.insert_message(
            {
                "message_id": STORE.next_id("msg"),
                "room_id": room_id,
                "sender_type": "agent",
                "sender_user_id": None,
                "sender_agent_id": agent["agent_id"],
                "visibility": "room",
                "content_type": "text",
                "text": ai_text,
                "delivery_mode": payload["delivery_mode"],
                "history_state": "active",
                "replaced_by_message_id": None,
                "source_task_id": None,
                "token_estimate": None,
                "created_at": response_at,
            }
        )

    task_info: List[dict] = [
        {
            "task_id": routing_decision["routing_id"],
            "agent_id": agent["agent_id"],
            "status": "done",
            "response_message_id": agent_message["message_id"],
        }
    ]
    return user_message, task_info
