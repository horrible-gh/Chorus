CREATE TABLE IF NOT EXISTS agent_presets (
    agent_id VARCHAR(64) PRIMARY KEY,
    owner_user_id VARCHAR(64) NOT NULL,
    display_name VARCHAR(120) NOT NULL,
    role_name VARCHAR(120) NOT NULL,
    description TEXT,
    default_runner VARCHAR(40) NOT NULL,
    default_model VARCHAR(120) NOT NULL,
    default_grade VARCHAR(20) NOT NULL,
    system_prompt TEXT NOT NULL,
    pinned_context TEXT,
    settings_json JSONB,
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'inactive', 'archived')),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS model_registry (
    model_id VARCHAR(80) PRIMARY KEY,
    runner VARCHAR(40) NOT NULL,
    model_name VARCHAR(120) NOT NULL,
    grade VARCHAR(20) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    estimated_cost_rank INTEGER NOT NULL,
    priority INTEGER NOT NULL,
    max_context_tokens INTEGER,
    provider_options_json JSONB,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    UNIQUE (runner, model_name)
);

CREATE TABLE IF NOT EXISTS chat_rooms (
    room_id VARCHAR(64) PRIMARY KEY,
    owner_user_id VARCHAR(64) NOT NULL,
    title VARCHAR(200) NOT NULL,
    mode VARCHAR(40) NOT NULL CHECK (mode IN ('append_history', 'one_shot')),
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'archived', 'deleted')),
    active_history_mode VARCHAR(40) NOT NULL CHECK (active_history_mode IN ('raw', 'compressed')),
    base_summary_message_id VARCHAR(64),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    archived_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS chat_participants (
    participant_id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL REFERENCES chat_rooms(room_id),
    participant_type VARCHAR(20) NOT NULL CHECK (participant_type IN ('user', 'agent')),
    user_id VARCHAR(64),
    agent_id VARCHAR(64) REFERENCES agent_presets(agent_id),
    display_name VARCHAR(120) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'inactive')),
    joined_at TIMESTAMP NOT NULL,
    left_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS messages (
    message_id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL REFERENCES chat_rooms(room_id),
    sender_type VARCHAR(20) NOT NULL CHECK (sender_type IN ('user', 'agent', 'system')),
    sender_user_id VARCHAR(64),
    sender_agent_id VARCHAR(64) REFERENCES agent_presets(agent_id),
    visibility VARCHAR(30) NOT NULL CHECK (visibility IN ('room', 'whisper', 'compression', 'private')),
    content_type VARCHAR(30) NOT NULL CHECK (content_type IN ('text', 'summary', 'event', 'error')),
    text TEXT NOT NULL,
    delivery_mode VARCHAR(40) NOT NULL CHECK (delivery_mode IN ('append_history', 'one_shot')),
    history_state VARCHAR(40) NOT NULL CHECK (history_state IN ('active', 'compressed_replaced', 'excluded')),
    replaced_by_message_id VARCHAR(64) REFERENCES messages(message_id),
    source_task_id VARCHAR(64),
    token_estimate INTEGER,
    created_at TIMESTAMP NOT NULL
);

ALTER TABLE chat_rooms
    ADD CONSTRAINT fk_chat_rooms_base_summary
    FOREIGN KEY (base_summary_message_id) REFERENCES messages(message_id);

CREATE TABLE IF NOT EXISTS message_recipients (
    message_recipient_id VARCHAR(64) PRIMARY KEY,
    message_id VARCHAR(64) NOT NULL REFERENCES messages(message_id),
    recipient_type VARCHAR(20) NOT NULL CHECK (recipient_type IN ('user', 'agent')),
    recipient_user_id VARCHAR(64),
    recipient_agent_id VARCHAR(64) REFERENCES agent_presets(agent_id),
    created_at TIMESTAMP NOT NULL,
    UNIQUE (message_id, recipient_type, recipient_user_id, recipient_agent_id)
);

CREATE TABLE IF NOT EXISTS routing_decisions (
    routing_id VARCHAR(64) PRIMARY KEY,
    request_id VARCHAR(80) NOT NULL,
    source VARCHAR(40) NOT NULL CHECK (source IN ('agent_chat', 'worker_loop', 'manual')),
    room_id VARCHAR(64) REFERENCES chat_rooms(room_id),
    message_id VARCHAR(64) REFERENCES messages(message_id),
    task_id VARCHAR(64),
    agent_id VARCHAR(64) REFERENCES agent_presets(agent_id),
    task_intent VARCHAR(60) NOT NULL,
    risk_score INTEGER NOT NULL,
    complexity_score INTEGER NOT NULL,
    confidence DECIMAL(5,4) NOT NULL,
    selected_runner VARCHAR(40),
    selected_model VARCHAR(120),
    selected_grade VARCHAR(20),
    decision VARCHAR(30) NOT NULL CHECK (decision IN ('selected', 'escalated', 'blocked')),
    reason_code VARCHAR(80) NOT NULL,
    reason_text TEXT NOT NULL,
    requires_review BOOLEAN NOT NULL DEFAULT FALSE,
    escalation_target VARCHAR(40),
    created_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
    task_id VARCHAR(64) PRIMARY KEY,
    created_by_user_id VARCHAR(64),
    source VARCHAR(40) NOT NULL CHECK (source IN ('manual', 'agent_chat', 'recovery', 'system')),
    title VARCHAR(200) NOT NULL,
    task_type VARCHAR(60) NOT NULL,
    priority VARCHAR(20) NOT NULL CHECK (priority IN ('low', 'normal', 'high')),
    status VARCHAR(40) NOT NULL CHECK (status IN ('queued', 'running', 'retry_scheduled', 'review_required', 'done', 'failed', 'blocked', 'cancelled')),
    assigned_agent_id VARCHAR(64) REFERENCES agent_presets(agent_id),
    routing_id VARCHAR(64) REFERENCES routing_decisions(routing_id),
    assigned_runner VARCHAR(40),
    assigned_model VARCHAR(120),
    assigned_grade VARCHAR(20),
    attempt INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 3,
    input_json JSONB NOT NULL,
    constraints_json JSONB NOT NULL,
    result_json JSONB,
    failure_code VARCHAR(80),
    failure_text TEXT,
    next_run_at TIMESTAMP,
    last_progress_at TIMESTAMP,
    last_progress_message TEXT,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS worker_leases (
    lease_id VARCHAR(64) PRIMARY KEY,
    task_id VARCHAR(64) NOT NULL REFERENCES tasks(task_id),
    job_id VARCHAR(80) NOT NULL UNIQUE,
    worker_id VARCHAR(80) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'released', 'expired', 'cancelled')),
    acquired_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    released_at TIMESTAMP,
    trace_id VARCHAR(80) NOT NULL
);

CREATE TABLE IF NOT EXISTS worker_runs (
    run_id VARCHAR(64) PRIMARY KEY,
    task_id VARCHAR(64) NOT NULL REFERENCES tasks(task_id),
    lease_id VARCHAR(64) REFERENCES worker_leases(lease_id),
    worker_id VARCHAR(80) NOT NULL,
    runner VARCHAR(40) NOT NULL,
    model VARCHAR(120) NOT NULL,
    grade VARCHAR(20) NOT NULL,
    attempt INTEGER NOT NULL,
    result_status VARCHAR(30) NOT NULL CHECK (result_status IN ('succeeded', 'failed', 'cancelled')),
    summary TEXT,
    artifact_paths_json JSONB,
    log_path TEXT,
    failure_code VARCHAR(80),
    failure_text TEXT,
    started_at TIMESTAMP NOT NULL,
    finished_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS context_compressions (
    compression_id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL REFERENCES chat_rooms(room_id),
    target_agent_id VARCHAR(64) NOT NULL REFERENCES agent_presets(agent_id),
    requested_by_user_id VARCHAR(64) NOT NULL,
    request_message_id VARCHAR(64) NOT NULL REFERENCES messages(message_id),
    task_id VARCHAR(64) REFERENCES tasks(task_id),
    status VARCHAR(30) NOT NULL CHECK (status IN ('queued', 'running', 'succeeded', 'failed')),
    ratio_before DECIMAL(5,4),
    ratio_after DECIMAL(5,4),
    original_token_estimate INTEGER,
    summary_token_estimate INTEGER,
    summary_message_id VARCHAR(64) REFERENCES messages(message_id),
    replaced_until_message_id VARCHAR(64) REFERENCES messages(message_id),
    failure_code VARCHAR(80),
    failure_text TEXT,
    created_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS room_events (
    event_id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL REFERENCES chat_rooms(room_id),
    event_type VARCHAR(60) NOT NULL,
    actor_user_id VARCHAR(64),
    actor_agent_id VARCHAR(64) REFERENCES agent_presets(agent_id),
    payload_json JSONB,
    text TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_agent_presets_owner_status ON agent_presets(owner_user_id, status);
CREATE INDEX IF NOT EXISTS idx_agent_presets_grade ON agent_presets(default_grade);
CREATE INDEX IF NOT EXISTS idx_model_registry_active_grade ON model_registry(is_active, grade);
CREATE INDEX IF NOT EXISTS idx_model_registry_cost ON model_registry(estimated_cost_rank, priority);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_owner_status ON chat_rooms(owner_user_id, status, updated_at);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_summary ON chat_rooms(base_summary_message_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_room_status ON chat_participants(room_id, status);
CREATE INDEX IF NOT EXISTS idx_messages_room_created ON messages(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_messages_room_history ON messages(room_id, history_state, created_at);
CREATE INDEX IF NOT EXISTS idx_message_recipients_agent ON message_recipients(recipient_agent_id, message_id);
CREATE INDEX IF NOT EXISTS idx_message_recipients_user ON message_recipients(recipient_user_id, message_id);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_task ON routing_decisions(task_id, created_at);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_message ON routing_decisions(message_id, created_at);
CREATE INDEX IF NOT EXISTS idx_routing_decisions_model ON routing_decisions(selected_runner, selected_model, created_at);
CREATE INDEX IF NOT EXISTS idx_tasks_status_priority ON tasks(status, priority, created_at);
CREATE INDEX IF NOT EXISTS idx_tasks_next_run ON tasks(status, next_run_at);
CREATE INDEX IF NOT EXISTS idx_tasks_agent_status ON tasks(assigned_agent_id, status);
CREATE INDEX IF NOT EXISTS idx_worker_leases_task_status ON worker_leases(task_id, status, expires_at);
CREATE INDEX IF NOT EXISTS idx_worker_runs_task_attempt ON worker_runs(task_id, attempt);
CREATE INDEX IF NOT EXISTS idx_context_compressions_room ON context_compressions(room_id, created_at);
CREATE INDEX IF NOT EXISTS idx_room_events_room_created ON room_events(room_id, created_at);

