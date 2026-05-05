CREATE TABLE IF NOT EXISTS users (
    user_id        TEXT PRIMARY KEY,
    password       TEXT NOT NULL,
    email_verified INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT NOT NULL,
    plan_id        TEXT
);

CREATE INDEX IF NOT EXISTS idx_users_plan ON users(plan_id);
