CREATE TABLE IF NOT EXISTS agent_presets (
    agent_id TEXT PRIMARY KEY,
    owner_user_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role_name TEXT NOT NULL,
    description TEXT,
    default_runner TEXT NOT NULL,
    default_model TEXT NOT NULL,
    default_grade TEXT NOT NULL,
    system_prompt TEXT NOT NULL,
    pinned_context TEXT,
    settings_json TEXT,
    status TEXT NOT NULL CHECK (status IN ('active', 'inactive', 'archived')),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_agent_presets_owner_status ON agent_presets(owner_user_id, status);
CREATE INDEX IF NOT EXISTS idx_agent_presets_grade ON agent_presets(default_grade);

CREATE TABLE IF NOT EXISTS model_registry (
    model_id TEXT PRIMARY KEY,
    runner TEXT NOT NULL,
    model_name TEXT NOT NULL,
    grade TEXT NOT NULL,
    is_active INTEGER NOT NULL DEFAULT 1,
    is_default INTEGER NOT NULL DEFAULT 0,
    estimated_cost_rank INTEGER NOT NULL,
    priority INTEGER NOT NULL,
    max_context_tokens INTEGER,
    provider_options_json TEXT,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_model_registry_runner_model ON model_registry(runner, model_name);
CREATE INDEX IF NOT EXISTS idx_model_registry_active_grade ON model_registry(is_active, grade);
CREATE INDEX IF NOT EXISTS idx_model_registry_cost ON model_registry(estimated_cost_rank, priority);

CREATE TABLE IF NOT EXISTS chat_rooms (
    room_id TEXT PRIMARY KEY,
    owner_user_id TEXT NOT NULL,
    title TEXT NOT NULL,
    mode TEXT NOT NULL CHECK (mode IN ('append_history', 'one_shot')),
    status TEXT NOT NULL CHECK (status IN ('active', 'archived', 'deleted')),
    active_history_mode TEXT NOT NULL CHECK (active_history_mode IN ('raw', 'compressed')),
    base_summary_message_id TEXT,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    archived_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_owner_status ON chat_rooms(owner_user_id, status, updated_at);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_summary ON chat_rooms(base_summary_message_id);

CREATE TABLE IF NOT EXISTS chat_participants (
    participant_id TEXT PRIMARY KEY,
    room_id TEXT NOT NULL REFERENCES chat_rooms(room_id),
    participant_type TEXT NOT NULL CHECK (participant_type IN ('user', 'agent')),
    user_id TEXT,
    agent_id TEXT REFERENCES agent_presets(agent_id),
    display_name TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'inactive')),
    joined_at TIMESTAMP NOT NULL,
    left_at TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_chat_participants_room_user ON chat_participants(room_id, user_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_chat_participants_room_agent ON chat_participants(room_id, agent_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_room_status ON chat_participants(room_id, status);

CREATE TABLE IF NOT EXISTS messages (
    message_id TEXT PRIMARY KEY,
    room_id TEXT NOT NULL REFERENCES chat_rooms(room_id),
    sender_type TEXT NOT NULL CHECK (sender_type IN ('user', 'agent', 'system')),
    sender_user_id TEXT,
    sender_agent_id TEXT REFERENCES agent_presets(agent_id),
    visibility TEXT NOT NULL CHECK (visibility IN ('room', 'whisper', 'compression', 'private')),
    content_type TEXT NOT NULL CHECK (content_type IN ('text', 'summary', 'event', 'error')),
    text TEXT NOT NULL,
    delivery_mode TEXT NOT NULL CHECK (delivery_mode IN ('append_history', 'one_shot')),
    history_state TEXT NOT NULL CHECK (history_state IN ('active', 'compressed_replaced', 'excluded')),
    replaced_by_message_id TEXT REFERENCES messages(message_id),
    source_task_id TEXT,
    token_estimate INTEGER,
    created_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_messages_room_created ON messages(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_room_history ON messages(room_id, history_state, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_source_task ON messages(source_task_id);
CREATE INDEX IF NOT EXISTS idx_messages_replaced_by ON messages(replaced_by_message_id);

CREATE TABLE IF NOT EXISTS message_recipients (
    message_recipient_id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL REFERENCES messages(message_id),
    recipient_type TEXT NOT NULL CHECK (recipient_type IN ('user', 'agent')),
    recipient_user_id TEXT,
    recipient_agent_id TEXT REFERENCES agent_presets(agent_id),
    created_at TIMESTAMP NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_message_recipients_unique ON message_recipients(message_id, recipient_type, recipient_user_id, recipient_agent_id);
CREATE INDEX IF NOT EXISTS idx_message_recipients_agent ON message_recipients(recipient_agent_id, message_id);
CREATE INDEX IF NOT EXISTS idx_message_recipients_user ON message_recipients(recipient_user_id, message_id);

CREATE TABLE IF NOT EXISTS routing_decisions (
    routing_id TEXT PRIMARY KEY,
    request_id TEXT NOT NULL,
    source TEXT NOT NULL CHECK (source IN ('agent_chat', 'worker_loop', 'manual')),
    room_id TEXT REFERENCES chat_rooms(room_id),
    message_id TEXT REFERENCES messages(message_id),
    task_id TEXT,
    agent_id TEXT REFERENCES agent_presets(agent_id),
    task_intent TEXT NOT NULL,
    risk_score INTEGER NOT NULL,
    complexity_score INTEGER NOT NULL,
    confidence REAL NOT NULL,
    selected_runner TEXT,
    selected_model TEXT,
    selected_grade TEXT,
    decision TEXT NOT NULL CHECK (decision IN ('selected', 'escalated', 'blocked')),
    reason_code TEXT NOT NULL,
    reason_text TEXT NOT NULL,
    requires_review INTEGER NOT NULL DEFAULT 0,
    escalation_target TEXT,
    created_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_routing_decisions_task ON routing_decisions(task_id, created_at);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_message ON routing_decisions(message_id, created_at);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_model ON routing_decisions(selected_runner, selected_model, created_at);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_decision ON routing_decisions(decision, reason_code);

CREATE TABLE IF NOT EXISTS tasks (
    task_id TEXT PRIMARY KEY,
    created_by_user_id TEXT,
    source TEXT NOT NULL CHECK (source IN ('manual', 'agent_chat', 'recovery', 'system')),
    title TEXT NOT NULL,
    task_type TEXT NOT NULL,
    priority TEXT NOT NULL CHECK (priority IN ('low', 'normal', 'high')),
    status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'retry_scheduled', 'review_required', 'done', 'failed', 'blocked', 'cancelled')),
    assigned_agent_id TEXT REFERENCES agent_presets(agent_id),
    routing_id TEXT REFERENCES routing_decisions(routing_id),
    assigned_runner TEXT,
    assigned_model TEXT,
    assigned_grade TEXT,
    attempt INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 3,
    input_json TEXT NOT NULL,
    constraints_json TEXT NOT NULL,
    result_json TEXT,
    failure_code TEXT,
    failure_text TEXT,
    next_run_at TIMESTAMP,
    last_progress_at TIMESTAMP,
    last_progress_message TEXT,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_tasks_status_priority ON tasks(status, priority, created_at);
CREATE INDEX IF NOT EXISTS idx_tasks_next_run ON tasks(status, next_run_at);
CREATE INDEX IF NOT EXISTS idx_tasks_agent_status ON tasks(assigned_agent_id, status);
CREATE INDEX IF NOT EXISTS idx_tasks_routing ON tasks(routing_id);

CREATE TABLE IF NOT EXISTS worker_leases (
    lease_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks(task_id),
    job_id TEXT NOT NULL,
    worker_id TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'released', 'expired', 'cancelled')),
    acquired_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    released_at TIMESTAMP,
    trace_id TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_worker_leases_task_status ON worker_leases(task_id, status, expires_at);
CREATE INDEX IF NOT EXISTS idx_worker_leases_worker ON worker_leases(worker_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS ux_worker_leases_job ON worker_leases(job_id);

CREATE TABLE IF NOT EXISTS worker_runs (
    run_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks(task_id),
    lease_id TEXT REFERENCES worker_leases(lease_id),
    worker_id TEXT NOT NULL,
    runner TEXT NOT NULL,
    model TEXT NOT NULL,
    grade TEXT NOT NULL,
    attempt INTEGER NOT NULL,
    result_status TEXT NOT NULL CHECK (result_status IN ('succeeded', 'failed', 'cancelled')),
    summary TEXT,
    artifact_paths_json TEXT,
    log_path TEXT,
    failure_code TEXT,
    failure_text TEXT,
    started_at TIMESTAMP NOT NULL,
    finished_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_worker_runs_task_attempt ON worker_runs(task_id, attempt);
CREATE INDEX IF NOT EXISTS idx_worker_runs_worker_time ON worker_runs(worker_id, started_at);
CREATE INDEX IF NOT EXISTS idx_worker_runs_result ON worker_runs(result_status, failure_code);

CREATE TABLE IF NOT EXISTS context_compressions (
    compression_id TEXT PRIMARY KEY,
    room_id TEXT NOT NULL REFERENCES chat_rooms(room_id),
    target_agent_id TEXT NOT NULL REFERENCES agent_presets(agent_id),
    requested_by_user_id TEXT NOT NULL,
    request_message_id TEXT NOT NULL REFERENCES messages(message_id),
    task_id TEXT REFERENCES tasks(task_id),
    status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
    ratio_before REAL,
    ratio_after REAL,
    original_token_estimate INTEGER,
    summary_token_estimate INTEGER,
    summary_message_id TEXT REFERENCES messages(message_id),
    replaced_until_message_id TEXT REFERENCES messages(message_id),
    failure_code TEXT,
    failure_text TEXT,
    created_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_context_compressions_room ON context_compressions(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_context_compressions_task ON context_compressions(task_id);
CREATE INDEX IF NOT EXISTS idx_context_compressions_summary ON context_compressions(summary_message_id);

CREATE TABLE IF NOT EXISTS room_events (
    event_id TEXT PRIMARY KEY,
    room_id TEXT NOT NULL REFERENCES chat_rooms(room_id),
    event_type TEXT NOT NULL,
    actor_user_id TEXT,
    actor_agent_id TEXT REFERENCES agent_presets(agent_id),
    payload_json TEXT,
    text TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_room_events_room_created ON room_events(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_room_events_type ON room_events(event_type, created_at);

