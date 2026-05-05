CREATE TABLE IF NOT EXISTS server_config (
    scope      TEXT NOT NULL,
    key1       TEXT NOT NULL,
    key2       TEXT NOT NULL DEFAULT '',
    key3       TEXT NOT NULL DEFAULT '',
    value      TEXT,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (scope, key1, key2, key3)
);
