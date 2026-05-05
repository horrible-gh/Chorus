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
    settings_json JSON,
    status VARCHAR(20) NOT NULL,
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
    provider_options_json JSON,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    UNIQUE KEY ux_model_registry_runner_model (runner, model_name)
);

CREATE TABLE IF NOT EXISTS chat_rooms (
    room_id VARCHAR(64) PRIMARY KEY,
    owner_user_id VARCHAR(64) NOT NULL,
    title VARCHAR(200) NOT NULL,
    mode VARCHAR(40) NOT NULL,
    status VARCHAR(20) NOT NULL,
    active_history_mode VARCHAR(40) NOT NULL,
    base_summary_message_id VARCHAR(64),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    archived_at TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS chat_participants (
    participant_id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL,
    participant_type VARCHAR(20) NOT NULL,
    user_id VARCHAR(64),
    agent_id VARCHAR(64),
    display_name VARCHAR(120) NOT NULL,
    status VARCHAR(20) NOT NULL,
    joined_at TIMESTAMP NOT NULL,
    left_at TIMESTAMP NULL,
    CONSTRAINT fk_chat_participants_room FOREIGN KEY (room_id) REFERENCES chat_rooms(room_id),
    CONSTRAINT fk_chat_participants_agent FOREIGN KEY (agent_id) REFERENCES agent_presets(agent_id)
);

CREATE TABLE IF NOT EXISTS messages (
    message_id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL,
    sender_type VARCHAR(20) NOT NULL,
    sender_user_id VARCHAR(64),
    sender_agent_id VARCHAR(64),
    visibility VARCHAR(30) NOT NULL,
    content_type VARCHAR(30) NOT NULL,
    text TEXT NOT NULL,
    delivery_mode VARCHAR(40) NOT NULL,
    history_state VARCHAR(40) NOT NULL,
    replaced_by_message_id VARCHAR(64),
    source_task_id VARCHAR(64),
    token_estimate INTEGER,
    created_at TIMESTAMP NOT NULL,
    CONSTRAINT fk_messages_room FOREIGN KEY (room_id) REFERENCES chat_rooms(room_id),
    CONSTRAINT fk_messages_sender_agent FOREIGN KEY (sender_agent_id) REFERENCES agent_presets(agent_id)
);

CREATE TABLE IF NOT EXISTS message_recipients (
    message_recipient_id VARCHAR(64) PRIMARY KEY,
    message_id VARCHAR(64) NOT NULL,
    recipient_type VARCHAR(20) NOT NULL,
    recipient_user_id VARCHAR(64),
    recipient_agent_id VARCHAR(64),
    created_at TIMESTAMP NOT NULL,
    CONSTRAINT fk_message_recipients_message FOREIGN KEY (message_id) REFERENCES messages(message_id),
    CONSTRAINT fk_message_recipients_agent FOREIGN KEY (recipient_agent_id) REFERENCES agent_presets(agent_id)
);

CREATE TABLE IF NOT EXISTS routing_decisions (
    routing_id VARCHAR(64) PRIMARY KEY,
    request_id VARCHAR(80) NOT NULL,
    source VARCHAR(40) NOT NULL,
    room_id VARCHAR(64),
    message_id VARCHAR(64),
    task_id VARCHAR(64),
    agent_id VARCHAR(64),
    task_intent VARCHAR(60) NOT NULL,
    risk_score INTEGER NOT NULL,
    complexity_score INTEGER NOT NULL,
    confidence DECIMAL(5,4) NOT NULL,
    selected_runner VARCHAR(40),
    selected_model VARCHAR(120),
    selected_grade VARCHAR(20),
    decision VARCHAR(30) NOT NULL,
    reason_code VARCHAR(80) NOT NULL,
    reason_text TEXT NOT NULL,
    requires_review BOOLEAN NOT NULL DEFAULT FALSE,
    escalation_target VARCHAR(40),
    created_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
    task_id VARCHAR(64) PRIMARY KEY,
    created_by_user_id VARCHAR(64),
    source VARCHAR(40) NOT NULL,
    title VARCHAR(200) NOT NULL,
    task_type VARCHAR(60) NOT NULL,
    priority VARCHAR(20) NOT NULL,
    status VARCHAR(40) NOT NULL,
    assigned_agent_id VARCHAR(64),
    routing_id VARCHAR(64),
    assigned_runner VARCHAR(40),
    assigned_model VARCHAR(120),
    assigned_grade VARCHAR(20),
    attempt INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 3,
    input_json JSON NOT NULL,
    constraints_json JSON NOT NULL,
    result_json JSON,
    failure_code VARCHAR(80),
    failure_text TEXT,
    next_run_at TIMESTAMP NULL,
    last_progress_at TIMESTAMP NULL,
    last_progress_message TEXT,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS worker_leases (
    lease_id VARCHAR(64) PRIMARY KEY,
    task_id VARCHAR(64) NOT NULL,
    job_id VARCHAR(80) NOT NULL UNIQUE,
    worker_id VARCHAR(80) NOT NULL,
    status VARCHAR(20) NOT NULL,
    acquired_at TIMESTAMP NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    released_at TIMESTAMP NULL,
    trace_id VARCHAR(80) NOT NULL,
    CONSTRAINT fk_worker_leases_task FOREIGN KEY (task_id) REFERENCES tasks(task_id)
);

CREATE TABLE IF NOT EXISTS worker_runs (
    run_id VARCHAR(64) PRIMARY KEY,
    task_id VARCHAR(64) NOT NULL,
    lease_id VARCHAR(64),
    worker_id VARCHAR(80) NOT NULL,
    runner VARCHAR(40) NOT NULL,
    model VARCHAR(120) NOT NULL,
    grade VARCHAR(20) NOT NULL,
    attempt INTEGER NOT NULL,
    result_status VARCHAR(30) NOT NULL,
    summary TEXT,
    artifact_paths_json JSON,
    log_path TEXT,
    failure_code VARCHAR(80),
    failure_text TEXT,
    started_at TIMESTAMP NOT NULL,
    finished_at TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS context_compressions (
    compression_id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL,
    target_agent_id VARCHAR(64) NOT NULL,
    requested_by_user_id VARCHAR(64) NOT NULL,
    request_message_id VARCHAR(64) NOT NULL,
    task_id VARCHAR(64),
    status VARCHAR(30) NOT NULL,
    ratio_before DECIMAL(5,4),
    ratio_after DECIMAL(5,4),
    original_token_estimate INTEGER,
    summary_token_estimate INTEGER,
    summary_message_id VARCHAR(64),
    replaced_until_message_id VARCHAR(64),
    failure_code VARCHAR(80),
    failure_text TEXT,
    created_at TIMESTAMP NOT NULL,
    completed_at TIMESTAMP NULL
);

CREATE TABLE IF NOT EXISTS room_events (
    event_id VARCHAR(64) PRIMARY KEY,
    room_id VARCHAR(64) NOT NULL,
    event_type VARCHAR(60) NOT NULL,
    actor_user_id VARCHAR(64),
    actor_agent_id VARCHAR(64),
    payload_json JSON,
    text TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL
);

CREATE INDEX idx_agent_presets_owner_status ON agent_presets(owner_user_id, status);
CREATE INDEX idx_model_registry_active_grade ON model_registry(is_active, grade);
CREATE INDEX idx_chat_rooms_owner_status ON chat_rooms(owner_user_id, status, updated_at);
CREATE INDEX idx_chat_participants_room_status ON chat_participants(room_id, status);
CREATE INDEX idx_messages_room_created ON messages(room_id, created_at);
CREATE INDEX idx_message_recipients_agent ON message_recipients(recipient_agent_id, message_id);
CREATE INDEX idx_routing_decisions_task ON routing_decisions(task_id, created_at);
CREATE INDEX idx_tasks_status_priority ON tasks(status, priority, created_at);
CREATE INDEX idx_worker_leases_task_status ON worker_leases(task_id, status, expires_at);
CREATE INDEX idx_worker_runs_task_attempt ON worker_runs(task_id, attempt);
CREATE INDEX idx_context_compressions_room ON context_compressions(room_id, created_at);
CREATE INDEX idx_room_events_room_created ON room_events(room_id, created_at);

