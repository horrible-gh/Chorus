CREATE TABLE IF NOT EXISTS agent_presets (
    agent_id TEXT PRIMARY KEY,
    owner_user_id TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role_name TEXT,
    description TEXT,
    default_runner TEXT NOT NULL DEFAULT 'copilot',
    default_model TEXT NOT NULL DEFAULT 'gpt-5-mini',
    default_grade TEXT,
    system_prompt TEXT,
    pinned_context TEXT,
    settings_json TEXT NOT NULL DEFAULT '{}',
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_agent_presets_owner_status
    ON agent_presets(owner_user_id, status);
