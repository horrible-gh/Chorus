INSERT INTO model_registry (
    model_id, runner, model_name, grade,
    is_active, is_default, estimated_cost_rank, priority,
    max_context_tokens, provider_options_json, created_at, updated_at
) VALUES
    ('model_claude_haiku_45', 'claude', 'claude-haiku-4.5', '0.33급',
     TRUE, TRUE, 1, 100, NULL, NULL, NOW(), NOW()),
    ('model_codex_gpt_54_mini', 'codex', 'gpt-5.4-mini', '0.33급',
     TRUE, TRUE, 2, 100, NULL, NULL, NOW(), NOW()),
    ('model_codex_gpt_53_codex', 'codex', 'gpt-5.3-codex', '1급',
     TRUE, FALSE, 5, 90, NULL, NULL, NOW(), NOW()),
    ('model_codex_gpt_54', 'codex', 'gpt-5.4', '1급',
     TRUE, FALSE, 4, 90, NULL, NULL, NOW(), NOW()),
    ('model_gemini_3_flash', 'gemini', 'gemini-3-flash-preview', '0.33급',
     TRUE, TRUE, 2, 100, NULL, NULL, NOW(), NOW()),
    ('model_gemini_31_flash_lite', 'gemini', 'gemini-3.1-flash-lite-preview', '0.33급',
     TRUE, FALSE, 2, 100, NULL, NULL, NOW(), NOW())
ON CONFLICT (runner, model_name) DO NOTHING;

UPDATE model_registry
SET is_active = TRUE, updated_at = NOW()
WHERE runner = 'copilot' AND model_name = 'gpt-4.1' AND is_active = FALSE;
