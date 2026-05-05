CREATE TABLE IF NOT EXISTS plans (
    plan_id    TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    ttl_days   INTEGER,
    quota_mb   INTEGER,
    storage_gb REAL,
    is_default INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
