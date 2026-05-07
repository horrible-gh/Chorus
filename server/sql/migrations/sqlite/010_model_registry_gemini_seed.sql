INSERT OR IGNORE INTO model_registry (
    model_id, runner, model_name, grade,
    is_active, is_default, estimated_cost_rank, priority,
    max_context_tokens, provider_options_json, created_at, updated_at
) VALUES
    ('model_gemini_runner_31_pro', 'gemini', 'gemini-3.1-pro-preview', '1급',
     1, 0, 6, 60, NULL, NULL, datetime('now'), datetime('now'));
