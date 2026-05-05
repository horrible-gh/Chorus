CREATE TABLE IF NOT EXISTS provider_tokens (
    token_id      TEXT PRIMARY KEY,
    owner_user_id TEXT NOT NULL,
    alias         TEXT NOT NULL,
    provider      TEXT NOT NULL,
    token_value   TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'active',
    created_at    TEXT NOT NULL,
    updated_at    TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_provider_tokens_owner_provider
    ON provider_tokens (owner_user_id, provider);
