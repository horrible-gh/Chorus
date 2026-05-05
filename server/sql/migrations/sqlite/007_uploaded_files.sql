CREATE TABLE IF NOT EXISTS uploaded_files (
    file_id       TEXT    PRIMARY KEY,
    owner_user_id TEXT    NOT NULL,
    original_name TEXT    NOT NULL,
    stored_path   TEXT    NOT NULL,
    size_bytes    INTEGER NOT NULL,
    mime_type     TEXT,
    status        TEXT    NOT NULL DEFAULT 'active',
    expires_at    TEXT,
    created_at    TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_uploaded_files_owner ON uploaded_files(owner_user_id, status, created_at);
