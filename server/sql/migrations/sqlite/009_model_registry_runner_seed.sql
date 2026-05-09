INSERT OR IGNORE INTO model_registry (
    model_id, runner, model_name, grade,
    is_active, is_default, estimated_cost_rank, priority,
    max_context_tokens, provider_options_json, created_at, updated_at
) VALUES
    ('model_claude_runner_sonnet_46', 'claude', 'claude-sonnet-4-6', 'Medium',
     1, 0, 5, 80, NULL, NULL, datetime('now'), datetime('now')),
    ('model_codex_runner_gpt55', 'codex', 'gpt-5.5', 'High',
     1, 0, 6, 70, NULL, NULL, datetime('now'), datetime('now'));
