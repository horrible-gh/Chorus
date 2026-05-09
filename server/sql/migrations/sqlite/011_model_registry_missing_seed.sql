INSERT OR IGNORE INTO model_registry (
    model_id, runner, model_name, grade,
    is_active, is_default, estimated_cost_rank, priority,
    max_context_tokens, provider_options_json, created_at, updated_at
) VALUES
    ('model_claude_haiku_45', 'claude', 'claude-haiku-4-5', 'Low',
     1, 1, 1, 100, NULL, NULL, datetime('now'), datetime('now')),
    ('model_codex_gpt_54_mini', 'codex', 'gpt-5.4-mini', 'Low',
     1, 1, 2, 100, NULL, NULL, datetime('now'), datetime('now')),
    ('model_codex_gpt_53_codex', 'codex', 'gpt-5.3-codex', 'Medium',
     1, 0, 5, 90, NULL, NULL, datetime('now'), datetime('now')),
    ('model_codex_gpt_54', 'codex', 'gpt-5.4', 'Medium',
     1, 0, 4, 90, NULL, NULL, datetime('now'), datetime('now')),
    ('model_gemini_3_flash', 'gemini', 'gemini-3-flash-preview', 'Low',
     1, 1, 2, 100, NULL, NULL, datetime('now'), datetime('now')),
    ('model_gemini_31_flash_lite', 'gemini', 'gemini-3.1-flash-lite-preview', 'Low',
     1, 0, 2, 100, NULL, NULL, datetime('now'), datetime('now'));

UPDATE model_registry
SET is_active = 1, updated_at = datetime('now')
WHERE runner = 'copilot' AND model_name = 'gpt-4.1' AND is_active = 0;
